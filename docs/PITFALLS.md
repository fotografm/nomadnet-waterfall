# Pitfalls

Every one of these cost real time. Most fail **silently**, or produce a symptom that points
somewhere else entirely. Each entry leads with the symptom, because that is what you will
have when you meet it.

---

## Micron rendering

### Partial URLs must be absolute

**Symptom:** the page shows a `⧖` placeholder for ever in one client, while another client
refreshes perfectly.

A Micron *partial* embeds another page and re-fetches it on an interval:

```
`{<32-hex destination hash>:/page/wf.mu`10`k=v|k=v}
```

NomadNet also accepts a **relative** form — `` `{:/page/wf.mu`10} `` — where the empty host
means "this node". **MeshChatX does not.** Its matcher is:

```js
/^`\{([a-f0-9]{32}):([^`}]*)(?:`(\d+)(?:`([^}]*))?)?\}$/
```

`([a-f0-9]{32})` is mandatory. The relative form never matches, so the partial is never
requested — and because the client still draws its loading placeholder, it looks like a slow
fetch rather than one that was never issued.

Two failure signatures that mean **different** things:

| what you see | meaning |
|---|---|
| stalled `⧖` | the directive parsed, but the request was never made — usually a URL the client won't match |
| raw markup on the page | the client has no partial support at all |

The absolute form works in both, since NomadNet's `parse_url` accepts `<32hex>:path` too.
**Always emit absolute.** Note also that the interval group is `(\d+)` — an integer. `10.0`
will not match.

### Colour must be 3-hex, not 24-bit

**Symptom:** the page fills with 4-character hex groups like `358B 2973 4BB6` instead of
colours.

NomadNet 1.4.3 accepts a 24-bit form, `` `FT30123B ``. Other clients implement only the
3-digit form: they consume `` `F `` plus exactly three characters and print the remainder as
text, so `` `FT30123B `` renders as colour `T30` followed by the visible text `123B`.

Verifying one parser is not verifying the client. Use `` `F<rgb> `` / `` `B<rgb> `` — at 64
palette steps it is visually identical, and the tags are shorter.

### Rendered width tracks style spans, not glyph count

**Symptom:** bursts do not line up vertically; the right-hand edge staircases.

Clients render each colour run as its own span and round each one. Run-length encoding gives
every row a different span count, so every row drifts by a different amount.

Fix, in two parts — the second is not optional:

1. Emit a tag for **every** cell, not only where the colour changes.
2. Guarantee **no two adjacent cells share a style**, or the client merges them back into
   runs and you are where you started. This code flips the low bit of the blue nibble when
   neighbours would otherwise match — 1/16 of one channel, invisible at this cell size.

### The ruler must be built the same way as the waterfall

**Symptom:** frequency markers span only ~70% of the image; the last tick sits well left of
the right edge, and the scale reads wrong.

A plain-text ruler line is a *single* span, so it renders far narrower than a line of `w`
one-cell spans. The label and tick lines are therefore emitted cell-by-cell with alternating
colours, exactly like a waterfall row. **All three line types must have identical span
counts.** Check with:

```sh
sed -n '4,7p' page.mu | awk '{n=gsub(/`B/,""); print n}'
```

### Every cell in a row must use the same glyph

**Symptom:** the right edge staircases, but only in one rendering mode.

Advance widths are not identical across glyphs, especially where a font falls back. Modes
that use a single glyph everywhere stay aligned; the quadrant mode, which picks from sixteen
glyphs by content, does not. That is why it is kept as a comparison button rather than a
recommendation.

### Subdividing time gives toothed edges

**Symptom:** solid blocks have spiky, comb-like tops and bottoms.

With two time rows per character row (`▀`, quadrants) a burst edge can land halfway through
a cell, so the block edge alternates between full and half height. Subdivide **frequency**
only and time edges always land on a row boundary.

### Never put a full block over a black background

**Symptom:** comb teeth along every solid edge.

Few fonts fill the entire cell with `U+2588`, so the background shows through as slivers. If
a group is uniform, paint it as a background cell with a **space** — and then the foreground
is a free channel for the anti-merge alternation.

### Alternate the foreground, never the background

`B001` against `B000` is RGB(0,0,17). It looks invisible in theory and produces obvious
vertical striping in practice. Style merging keys on style, not appearance, so alternating
the foreground alone is enough.

### Lines wider than the viewport wrap and destroy the image

**Symptom:** thin black bands between rows, with one or two stray coloured cells at the far
left of each.

The ruler often escapes it because trailing spaces get trimmed — so the waterfall wraps
while the ruler looks fine. Check true width with `tools/width.py`, which accounts for
zero-width colour tags and link labels.

---

## Talking to OpenWebRX

### Never switch the SDR profile

`activateProfile` lives on the **SdrSource**, not on the connection. There is one spectrum
stream per SDR, so selecting a profile **retunes the receiver for everyone watching it**.

This collector never sends `selectprofile`, `setsdr`, `setfrequency`, `dspcontrol`,
`connectionproperties` or `sendmessage`. Those six are *absent from the source*, not
guarded by a flag, so they cannot be re-enabled by accident. OpenWebRX also bans clients
that churn profiles, which is why reconnects use exponential backoff.

### Spectrum starts on its own

Do **not** send `dspcontrol start` — that is the audio path. `handleSdrAvailable()` registers
the spectrum client server-side; frames simply begin.

### Config arrives in several messages

Merge them. Do not expect one complete message. It is re-sent whenever anything changes,
which is how the page notices a retune.

### Decoding the FFT frames

Binary frames are type-tagged by the first byte; `0x01` is the waterfall. With
`fft_compression = adpcm` the payload is IMA-ADPCM:

1. Reset the codec **per frame**
2. Each byte yields two samples, **low nibble first**
3. Standard IMA index/step tables
4. **Drop the first 10 decoded samples** (`COMPRESS_FFT_PAD_N`)
5. **Divide by 100** to get dB

### The library keepalive fights OpenWebRX

**Symptom:** `ConnectionClosedError: sent 1011 ... keepalive ping timeout`, repeatedly.

When the receiver's SDR source fails, its websocket thread stalls and stops answering pings,
so the client tears down a connection that would have recovered. Use `ping_interval=None`
and rely on a `recv` timeout instead — liveness based on data actually arriving, which is
the thing you care about.

### A blank waterfall is usually the receiver

Check its log before suspecting your own code:

```
owrx.source.rtlsdr - WARNING - STDERR: No supported devices found.
owrx.source.rtlsdr - WARNING - STDERR: Connector::open() failed
```

That means the dongle has gone. Confirm with `lsusb` on the receiver.

---

## Everything else

### Keep the frequency geometry in *every* status write

**Symptom:** the page dies with `KeyError('f_lo')` whenever the collector disconnects.

The error path originally omitted `f_lo`/`f_hi`, so a disconnect turned a readable "not
connected" notice into a crash. Anything the page indexes unconditionally must be present in
every status write, not just the happy path.

### Page size is driven by colour churn, not by traffic

A dithered noise floor costs more bytes than the signals do. The two colour tags dominate at
10 bytes per cell; the glyph is 1 byte for a space and 3 for a UTF-8 block. So sub-character
modes cost exactly **+2 bytes per cell** — 4× the data for about 17% more bytes.

### Render every signal equally

Do not clamp the colour scale, squelch by default, or subtract a noise floor by default.

Per-bin median subtraction in particular removes fixed receiver spurs but **also erases any
constant carrier** — a whole class of signal vanishes and nothing tells you. Take the scale
from the observed data so the strongest emitter in view always reaches the top of the
palette, whatever it is, and keep such processing opt-in.

Name zoom presets by frequency, never by presumed signal type.

### NomadNet specifics

- `enable_client` is parsed and stored but **never consumed** — setting it does nothing.
- A *new* page file needs a NomadNet restart; edits to an existing one do not.
- `served_page_requests` is node-wide and, in 1.4.3, flushed to disk only once a minute.
  Keep a separate per-page counter if you want an honest number.
- `node_last_announce` on disk is not a reliable record of announce timing — `announce()`
  writes it but never marks settings dirty, so it lands only when something else triggers a
  flush.
