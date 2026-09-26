#!/usr/bin/env python3
"""
868 MHz waterfall collector.

Taps vm103's OpenWebRX spectrum websocket STRICTLY READ-ONLY: the only message
ever sent is the handshake line. It never sends selectprofile, setsdr,
setfrequency, dspcontrol, connectionproperties or sendmessage, so it cannot
retune or otherwise disturb the shared RTL-SDR. Those message types are
deliberately absent from this file rather than merely disabled.

Stores the FULL captured FFT span, unfiltered. Nothing is discarded or
attenuated here; selecting what to look at is the renderer's job, so any
signal vm103 can see reaches the page.
"""
import asyncio, json, os, time
import numpy as np
import websockets

OWRX_URI  = os.environ.get("OWRX_URI", "ws://192.168.8.103:8073/ws/")
CLIENT_ID = "ct119-waterfall"
ROWS      = 900          # 15 min of history at ROW_SECS
ROW_SECS  = 1.0
SHM       = "/dev/shm/waterfall"

# --- IMA ADPCM, exactly as OpenWebRX's client decodes the FFT stream ---------
IMA_INDEX = [-1,-1,-1,-1,2,4,6,8,-1,-1,-1,-1,2,4,6,8]
IMA_STEP = [7,8,9,10,11,12,13,14,16,17,
            19,21,23,25,28,31,34,37,41,45,
            50,55,60,66,73,80,88,97,107,118,
            130,143,157,173,190,209,230,253,279,307,
            337,371,408,449,494,544,598,658,724,796,
            876,963,1060,1166,1282,1411,1552,1707,1878,2066,
            2272,2499,2749,3024,3327,3660,4026,4428,4871,5358,
            5894,6484,7132,7845,8630,9493,10442,11487,12635,13899,
            15289,16818,18500,20350,22385,24623,27086,29794,32767]
PAD = 10   # COMPRESS_FFT_PAD_N

def decode_fft(data):
    """ADPCM nibbles -> dB floats. Codec state resets per frame."""
    si = 0; pred = 0; step = 0
    out = np.empty(len(data) * 2, dtype=np.float32)
    o = 0
    for b in data:
        for nib in (b & 0x0F, b >> 4):
            si += IMA_INDEX[nib]
            si = 0 if si < 0 else (88 if si > 88 else si)
            diff = step >> 3
            if nib & 1: diff += step >> 2
            if nib & 2: diff += step >> 1
            if nib & 4: diff += step
            if nib & 8: diff = -diff
            pred += diff
            pred = -32768 if pred < -32768 else (32767 if pred > 32767 else pred)
            step = IMA_STEP[si]
            out[o] = pred; o += 1
    return out[PAD:] / 100.0


class Ring:
    """Fixed-size tmpfs ring of max-held spectrum rows, full captured span."""
    def __init__(self, nbins):
        os.makedirs(SHM, exist_ok=True)
        self.nbins = nbins
        self.data  = np.memmap(f"{SHM}/ring.dat",  dtype=np.float32, mode="w+", shape=(ROWS, nbins))
        self.times = np.memmap(f"{SHM}/times.dat", dtype=np.float64, mode="w+", shape=(ROWS,))
        self.data[:] = np.nan
        self.times[:] = 0.0
        self.idx = 0

    def commit(self, row, ts):
        self.data[self.idx] = row
        self.times[self.idx] = ts
        self.idx = (self.idx + 1) % ROWS

    def gap(self, ts):
        self.data[self.idx] = np.nan
        self.times[self.idx] = ts
        self.idx = (self.idx + 1) % ROWS


def write_status(**kw):
    tmp = f"{SHM}/status.json.tmp"
    with open(tmp, "w") as f:
        json.dump(kw, f)
    os.replace(tmp, f"{SHM}/status.json")


async def run():
    os.makedirs(SHM, exist_ok=True)
    ring = None
    cfg = {}
    backoff = 2.0
    state = dict(connected=False, note="starting")

    while True:
        try:
            # ping_interval=None: OpenWebRX stalls its websocket thread
            # whenever its SDR source fails, which trips the library keepalive
            # and drops an otherwise healthy connection. The wait_for(recv)
            # below already provides data-based liveness detection.
            async with websockets.connect(OWRX_URI, max_size=None,
                                          open_timeout=15, close_timeout=5,
                                          ping_interval=None) as ws:
                # The one and only message we ever send.
                await ws.send(f"SERVER DE CLIENT client={CLIENT_ID} type=receiver")
                backoff = 2.0
                state.update(connected=True, note="ok")

                cur = None
                row_end = None
                nfft = None

                while True:
                    msg = await asyncio.wait_for(ws.recv(), timeout=30)

                    if isinstance(msg, str):
                        if msg.startswith("CLIENT DE SERVER"):
                            continue
                        try:
                            j = json.loads(msg)
                        except ValueError:
                            continue
                        # config arrives across several progressive messages
                        if j.get("type") == "config":
                            cfg.update({k: v for k, v in j.get("value", {}).items() if v is not None})
                            n = cfg.get("fft_size")
                            if n and (ring is None or ring.nbins != n):
                                ring = Ring(n)
                                row_end = None
                            nfft = n
                        continue

                    if msg[0] != 1 or ring is None or nfft is None:
                        continue

                    fft = decode_fft(msg[1:])
                    if len(fft) != ring.nbins:
                        continue

                    now = time.time()
                    if row_end is None:
                        row_end = (now // ROW_SECS) * ROW_SECS + ROW_SECS
                        cur = fft.copy()
                    elif now >= row_end:
                        ring.commit(cur, row_end)
                        missed = int((now - row_end) // ROW_SECS)
                        for m in range(min(missed, ROWS)):
                            ring.gap(row_end + (m + 1) * ROW_SECS)
                        row_end = (now // ROW_SECS) * ROW_SECS + ROW_SECS
                        cur = fft.copy()
                    else:
                        np.maximum(cur, fft, out=cur)   # peak hold within the row

                    cf, sr = cfg.get("center_freq"), cfg.get("samp_rate")
                    write_status(rows=ROWS, bins=ring.nbins, idx=int(ring.idx),
                                 row_secs=ROW_SECS,
                                 f_lo=cf - sr / 2, f_hi=cf + sr / 2,
                                 bin_hz=sr / ring.nbins,
                                 center_freq=cf, samp_rate=sr,
                                 profile_id=cfg.get("profile_id"),
                                 updated=now, **state)

        except Exception as e:
            state.update(connected=False, note=f"{type(e).__name__}: {e}"[:160])
            try:
                # Keep the frequency geometry in the status even while
                # disconnected: the ring still holds up to 15 minutes of valid
                # data, and without f_lo/f_hi the page cannot render any of it.
                cf, sr = cfg.get("center_freq"), cfg.get("samp_rate")
                geom = {}
                if cf and sr and ring:
                    geom = dict(f_lo=cf - sr / 2, f_hi=cf + sr / 2,
                                bin_hz=sr / ring.nbins,
                                center_freq=cf, samp_rate=sr,
                                profile_id=cfg.get("profile_id"))
                write_status(rows=ROWS, bins=(ring.nbins if ring else 0),
                             idx=int(ring.idx) if ring else 0, row_secs=ROW_SECS,
                             updated=time.time(), **geom, **state)
            except Exception:
                pass
            # Back off politely; vm103 bans clients that hammer it.
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 60.0)


if __name__ == "__main__":
    asyncio.run(run())
