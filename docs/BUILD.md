# Building it from scratch

Written so you can follow it on a fresh machine and understand *why* each step is the way
it is. Where a step exists to dodge a trap, it links to [PITFALLS.md](PITFALLS.md).

Target here is an unprivileged Debian 13 LXC, but nothing depends on that — any host with
Python 3 and network access to the receiver will do.

---

## 1. What you need first

- An **OpenWebRX** (or OpenWebRX+) receiver you can reach on the network. This project
  reads it; it does not configure it. You need no SDR of your own.
- A host for the page server. It is light: ~3% of one core and ~45 MB RSS.

Check the receiver answers:

```sh
curl -s -o /dev/null -w '%{http_code}\n' http://RECEIVER:8073/
```

---

## 2. Packages

```sh
apt-get install -y python3 python3-venv python3-numpy python3-websockets \
                   curl ca-certificates
```

NomadNet itself needs a venv, because modern Debian marks the system Python
externally-managed (PEP 668):

```sh
python3 -m venv --system-site-packages /opt/waterfall/venv
/opt/waterfall/venv/bin/pip install nomadnet
```

`--system-site-packages` matters: it lets the venv see the apt-installed numpy. The
collector and the page run the **system** `python3`; only NomadNet runs from the venv.

> If you ever add something to the page that needs `RNS` — reading `peersettings`, say —
> its shebang must change to the venv interpreter, because the system Python has no `RNS`
> and the read fails **silently**.

---

## 3. Install the files

```sh
install -Dm755 collector/collector.py /opt/waterfall/collector.py
install -Dm644 data/turbo.json        /opt/waterfall/turbo.json
install -Dm755 tools/nodehash.py tools/width.py /opt/waterfall/
install -Dm755 pages/index.mu pages/live.mu pages/wf.mu pages/test.mu \
               /root/.nomadnetwork/storage/pages/
install -Dm644 systemd/waterfall-collector.service \
               systemd/nomadnet.service /etc/systemd/system/
```

The pages **must be executable** — that is how NomadNet decides to run a page rather than
serve it verbatim. It checks this per request, so `chmod +x` takes effect immediately, but
a *new page file* needs a NomadNet restart before it is served at all.

> Anything left in the pages directory gets served, including editor backups and
> `__pycache__`. Keep it clean.

---

## 4. Configure

Edit the `CONFIG` block at the top of `pages/index.mu`:

```python
SHM        = "/dev/shm/waterfall"
NNSTORE    = "/root/.nomadnetwork/storage"
NODEHASH_F = "/opt/waterfall/nodehash.txt"
TURBO_F    = "/opt/waterfall/turbo.json"
DEF_LO, DEF_HI = 869_250_000, 869_800_000   # displayed window, not a filter
LXMF_ADDR  = ""                             # optional contact link
```

Point the collector at your receiver — it reads `OWRX_URI` from the environment:

```sh
systemctl edit waterfall-collector
# [Service]
# Environment=OWRX_URI=ws://192.168.8.103:8073/ws/
```

Cache the node's destination hash. **The auto-refresh partial needs this** and will not
work without it — see [PITFALLS.md](PITFALLS.md#partial-urls-must-be-absolute):

```sh
/opt/waterfall/venv/bin/python3 /opt/waterfall/nodehash.py \
  | awk '{print $2}' > /opt/waterfall/nodehash.txt
```

---

## 5. NomadNet node config

Generate the default config by starting it once, then set:

```
enable_node = yes
node_name = 868 MHz Mesh Waterfall
page_refresh_interval = 1
announce_interval = 15          # in the [node] section — minutes
```

> There are **two** `announce_interval` keys. The one in `[client]` is the LXMF peer
> address; the one in `[node]` is what makes your page server discoverable. Editing the
> wrong one changes nothing you care about.

---

## 6. Start it

```sh
systemctl daemon-reload
systemctl enable --now waterfall-collector nomadnet
```

Verify the tap is alive:

```sh
python3 -c 'import json;print(json.load(open("/dev/shm/waterfall/status.json")))'
```

You want `"connected": true` and a non-zero `bins`.

---

## 7. How it fits together

```
 OpenWebRX ──websocket──> collector.py ──> /dev/shm/waterfall ──> index.mu ──> NomadNet
  (read-only tap)          ADPCM decode      ring buffer          renderer      page
                           peak hold         15 min                            
```

**collector.py** connects, sends exactly one message — the handshake — and then only
receives. Spectrum frames start on their own; you never ask for them. It decodes each frame
(IMA-ADPCM), peak-holds ~9 frames into each 1-second row, and writes into a fixed ring in
tmpfs. It stores the **entire captured span**, unfiltered, so the page can zoom for free.

**index.mu** is one file with three modes, selected by query variable:

| mode | produces |
|---|---|
| default | the full static page |
| `var_live=1` | a thin wrapper page embedding the waterfall as an auto-refreshing partial |
| `var_part=1` | the ruler and waterfall alone — the partial's target |

`live.mu` and `wf.mu` are four-line shell wrappers that re-exec `index.mu` with those
variables set, so there is exactly one renderer to maintain.

---

## 8. Rendering, and why it is the way it is

A character cell can carry one foreground and one background colour. Every rendering mode
is a different way of spending those two colours:

| mode | glyph | per cell |
|---|---|---|
| dots (default) | `⣿` `▪` `•` `·` `●` | one level, as the mark |
| blocks | space | one level, as the background |
| hi-res | `▌` | two levels — left/right, 2× in frequency |
| quad | 16 quadrant glyphs | four levels squeezed into two colours |
| half | `▀` | two levels — top/bottom, 2× in time |

Three rules hold this together, each learned the hard way:

1. **Every cell in a row uses the same glyph.** Rendered width tracks glyphs and style
   spans; a varying glyph mix gives every row a different width and the right edge
   staircases.
2. **A tag on every cell, and no two neighbours sharing a style.** Clients merge equal
   adjacent styles and round each merged run, so run-length encoding makes rows drift.
3. **The ruler is built cell-by-cell too**, with the same span structure, or the frequency
   markers compress to ~70% of the image width and the scale reads wrong.

All three are explained with symptoms in [PITFALLS.md](PITFALLS.md).

---

## 9. Verify

```sh
# no line may exceed the intended width — wrapping destroys the image
/root/.nomadnetwork/storage/pages/index.mu > /tmp/p.mu
python3 /opt/waterfall/width.py /tmp/p.mu

# ruler and waterfall rows must have identical span counts
sed -n '4,7p' /tmp/p.mu | awk '{n=gsub(/`B/,""); print n}'
```

`pages/test.mu` renders calibration rows ending in a `|` marker. If those markers do not
form a straight vertical line, the client's width depends on something other than glyph
count, and the rows tell you which.

The real end-to-end test is fetching the page over Reticulum from another node.
