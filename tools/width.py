import sys
BT = '`'
def visible(line):
    out = []; i = 0
    while i < len(line):
        c = line[i]
        if c == '\\' and i + 1 < len(line):
            out.append(line[i+1]); i += 2; continue
        if c == BT:
            if i + 1 >= len(line): break
            n = line[i+1]
            if n == '[':                      # link: `[label`url] -> label
                end = line.find(']', i)
                if end == -1: i += 2; continue
                data = line[i+2:end]
                parts = data.split(BT)
                out.extend(parts[0] if len(parts) > 1 else data)
                i = end + 1; continue
            if n in '`_!*clrafb': i += 2; continue
            if n in 'FB':
                i += 9 if (i+2 < len(line) and line[i+2] == 'T') else 5
                continue
            i += 2; continue
        out.append(c); i += 1
    return len(out)

widths = {}
over = []
for num, ln in enumerate(open(sys.argv[1]), 1):
    w = visible(ln.rstrip('\n'))
    widths[w] = widths.get(w, 0) + 1
    if w > 80: over.append((num, w))
print("width histogram:", sorted(widths.items(), key=lambda x: -x[1])[:8])
print("lines wider than 80 glyphs:", over if over else "none")
