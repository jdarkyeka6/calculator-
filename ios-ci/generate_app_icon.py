#!/usr/bin/env python3
"""Generate a provisional opaque RGB 1024x1024 App Store calculator icon."""
from pathlib import Path
import struct
import zlib

SIZE=1024
OUT=Path("Calculator/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")

def chunk(kind, data):
    return struct.pack(">I",len(data))+kind+data+struct.pack(">I",zlib.crc32(kind+data)&0xffffffff)

def rounded(x,y,l,t,r,b,rad):
    a=min(max(x,l+rad),r-rad)
    q=min(max(y,t+rad),b-rad)
    return (x-a)**2+(y-q)**2<=rad**2

def rgb(x,y):
    k=(x+y)/(2*SIZE)
    bg=(int(9+12*k),int(14+18*k),int(36+40*k))
    if not rounded(x,y,150,100,870,925,100):
        return bg
    if rounded(x,y,215,180,805,355,28):
        return (25,110,127)
    if rounded(x,y,540,232,746,281,9):
        return (179,255,241)
    for row in range(4):
        for col in range(4):
            left=214+col*149
            top=405+row*116
            if rounded(x,y,left,top,left+125,top+91,22):
                return (247,160,74) if col==3 else (98,112,142)
    return (34,43,68)

raw=bytearray()
for y in range(SIZE):
    raw.append(0)
    for x in range(SIZE):
        raw.extend(rgb(x,y))
png=bytearray(b"\x89PNG\r\n\x1a\n")
png.extend(chunk(b"IHDR",struct.pack(">IIBBBBB",SIZE,SIZE,8,2,0,0,0)))
png.extend(chunk(b"IDAT",zlib.compress(bytes(raw),9)))
png.extend(chunk(b"IEND",b""))
OUT.parent.mkdir(parents=True,exist_ok=True)
OUT.write_bytes(png)
print("Generated 1024px opaque Calculator icon")
