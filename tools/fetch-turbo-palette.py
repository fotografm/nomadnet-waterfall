#!/usr/bin/env python3
"""
Extract the 256-entry Google Turbo palette from an OpenWebRX install.

The waterfall reproduces OpenWebRX's own colours so the page looks familiar
next to the receiver it is reading from. Rather than transcribe 256 hex values
by hand (and get one wrong), pull them straight out of the shipped UI.js.

    ./fetch-turbo-palette.py user@192.168.8.103 > ../data/turbo.json

Run with no argument to read a local UI.js path instead.
"""
import json, re, subprocess, sys

JS = "/usr/lib/python3/dist-packages/htdocs/lib/UI.js"

EXTRACT = (
    "python3 -c \"import re,json;"
    "s=open('%s').read();"
    "i=s.index(chr(39)+'turbo'+chr(39));j=s.index('[',i);k=s.index(']',j);"
    "print(json.dumps([int(x,16) for x in re.findall(r'0x([0-9A-Fa-f]{6})', s[j:k])]))\"" % JS
)

if len(sys.argv) > 1 and "@" in sys.argv[1]:
    out = subprocess.run(["ssh", "-o", "BatchMode=yes", sys.argv[1], EXTRACT],
                         capture_output=True, text=True, check=True).stdout
else:
    path = sys.argv[1] if len(sys.argv) > 1 else JS
    s = open(path).read()
    i = s.index("'turbo'"); j = s.index("[", i); k = s.index("]", j)
    out = json.dumps([int(x, 16) for x in re.findall(r"0x([0-9A-Fa-f]{6})", s[j:k])])

vals = json.loads(out)
if len(vals) != 256:
    sys.exit("expected 256 palette entries, got %d" % len(vals))
print(json.dumps(vals))
