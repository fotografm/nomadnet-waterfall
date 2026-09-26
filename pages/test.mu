#!/usr/bin/env python3
"""Render-alignment diagnostic. Every test row is exactly 72 cells wide and
ends with a white | marker. If the markers do not form a straight vertical
line, rendered width depends on something other than glyph count."""
BLOCK = "▀"
W = 72
A, B = "07F", "F70"

def emit(cells, tag):
    print("".join(cells) + "``|`F888" + tag + "``")

def runs(n):
    out, per = [], W // n
    for c in range(W):
        col = A if (c // per) % 2 == 0 else B
        if c % per == 0:
            out.append("`F" + col + "`B" + col)
        out.append(BLOCK)
    return out

def per_cell(same):
    out = []
    for c in range(W):
        col = A if (same or c % 2 == 0) else B
        out.append("`F" + col + "`B" + col + BLOCK)
    return out

print("`c`B112`Ffd0`! RENDER ALIGNMENT TEST ``")
print("`c`F777all rows are 72 cells - the | markers should form a straight line``")
print("-")
print("`F888" + ("....|" * 14) + "..``")
print("#" * W + "``|`F888 asc")
print(BLOCK * W + "``|`F888 blk")
print("-")
for n in (1, 2, 4, 8, 12, 24, 36, 72):
    emit(runs(n), " r%d" % n)
print("-")
emit(per_cell(True),  " tcS")
emit(per_cell(False), " tcA")
print("-")
emit(["`B" + A + " " for _ in range(W)], " spS")
emit(["`B" + (A if c % 2 == 0 else B) + " " for c in range(W)], " spA")
print("-")
print("`F777rN = N colour runs.  tcS/tcA = a tag on every cell, same/alt colour.``")
print("`F777spS/spA = spaces with background colour only.``")
print("`F777Markers staircase -> width depends on colour-run count.``")
print("`F777runs=1 vs runs=72 is the key comparison.``")
print("`F777tag/cell-same vs runs=1 differing -> renderer merges equal styles.``")
print("")
print("`[back to waterfall`:/page/index.mu]")
