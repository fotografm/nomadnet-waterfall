# NomadNet 868 MHz Waterfall

A live RF waterfall served as a **NomadNet page**, drawn in Micron markup — colour,
sub-character resolution, and optional auto-refresh, entirely out of text.

It reads its spectrum from an existing **OpenWebRX** receiver over that receiver's own
WebSocket, strictly read-only, so it needs no SDR hardware of its own and cannot disturb
the radio it borrows from.

```
                          868 MHz WATERFALL
   869.250 - 869.800 MHz  .  captured 868.48 - 870.52 MHz  .  vm103 RTL-SDR
                 Try the different rendering modes.
            I like the Braille one with brightness 100 best.
 ────────────────────────────────────────────────────────────────────────────
      869.3         869.4         869.5         869.6         869.7    869.8
        |             |             |             |             |        |
 ⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
 ⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿
 ────────────────────────────────────────────────────────────────────────────
 Live:   live waterfall (auto-refresh)
 Span:   1 min  2 min  5 min  15 min
 Render: blocks  hi-res  quad  half     Dots: square bullet middot circle braille
```

## What it does

- **Reads an existing receiver.** Taps OpenWebRX's spectrum WebSocket, decodes its
  IMA-ADPCM FFT frames, and keeps 15 minutes of peak-held spectrum in a tmpfs ring.
- **Never touches the radio.** The six message types that could retune or reconfigure the
  receiver are *absent from the source*, not disabled by a flag. See
  [docs/PITFALLS.md](docs/PITFALLS.md).
- **Shows every signal.** Raw dBFS, no squelch, no noise-floor subtraction, and a colour
  scale taken from the observed data — so the strongest emitter in view always reaches the
  top of the palette, whatever it happens to be.
- **Renders several ways.** Braille dots (default), solid blocks, half-blocks, and two
  sub-character modes that pack 2× or 4× the data into the same screen area.
- **Optionally refreshes itself** every N seconds via a Micron *partial*, in clients that
  support them.

## Quick start

You need a reachable OpenWebRX receiver and a host to run this on.

```sh
git clone https://github.com/fotografm/nomadnet-waterfall
cd nomadnet-waterfall
less docs/BUILD.md        # the full walkthrough
```

Short version:

```sh
apt-get install -y python3 python3-venv python3-numpy python3-websockets
python3 -m venv --system-site-packages /opt/waterfall/venv
/opt/waterfall/venv/bin/pip install nomadnet

install -Dm755 collector/collector.py /opt/waterfall/collector.py
install -Dm644 data/turbo.json        /opt/waterfall/turbo.json
install -Dm755 pages/*.mu             /root/.nomadnetwork/storage/pages/
install -Dm644 systemd/*.service      /etc/systemd/system/

# edit the CONFIG block at the top of pages/index.mu, then:
tools/nodehash.py > /opt/waterfall/nodehash.txt
systemctl enable --now waterfall-collector nomadnet
```

## Repository layout

| path | what |
|---|---|
| `collector/collector.py` | the read-only OpenWebRX WebSocket tap and ring buffer |
| `pages/index.mu` | the renderer — one file, three modes (`static`, `live`, `part`) |
| `pages/live.mu`, `pages/wf.mu` | four-line wrappers that re-exec `index.mu` in the other two modes |
| `pages/test.mu` | render-alignment diagnostic, for debugging a client's Micron output |
| `tools/nodehash.py` | prints the node's 32-hex destination hash |
| `tools/width.py` | checks a rendered page's true glyph width (wrapping destroys the image) |
| `tools/fetch-turbo-palette.py` | re-extracts the colour palette from an OpenWebRX host |
| `data/turbo.json` | 256-entry Google Turbo palette |
| `systemd/` | unit files for the collector and the NomadNet node |

## Documentation

- **[docs/BUILD.md](docs/BUILD.md)** — build it from scratch, step by step, with the
  reasoning for each choice.
- **[docs/PITFALLS.md](docs/PITFALLS.md)** — every trap found while building this, with the
  symptom that identifies each one. Read this before changing the rendering code; several
  of these fail *silently* or look like an unrelated problem.

## Client support

Micron is rendered by the client, so behaviour varies. Verified by reading each client's
parser, not by assumption:

| client | colour | partials (auto-refresh) |
|---|---|---|
| NomadNet 1.4.3 (terminal) | 3-hex and 24-bit | yes |
| MeshChatX 4.9.1 | 3-hex | yes |
| MeshChat | 3-hex | no |
| rBrowser | 3-hex | no |

**Always emit 3-hex colour** (`` `F0f0 ``). The 24-bit `` `FT00ff00 `` form exists in
NomadNet but clients that only implement 3-hex will consume three characters and print the
rest as literal text — a page full of stray hex digits.

## Licence

MIT — see [LICENSE](LICENSE).
