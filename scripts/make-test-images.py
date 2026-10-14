#!/usr/bin/env python3
"""Writes two small PNGs that differ in a known number of pixels, for smoke tests.

Usage: make-test-images.py <dir>
Creates <dir>/a.png and <dir>/b.png (64x48); b has a 10x5 block changed, so 50 pixels differ.
"""
import os
import struct
import sys
import zlib


def png(path, width, height, pixel):
    rows = b"".join(b"\0" + b"".join(bytes(pixel(x, y)) for x in range(width)) for y in range(height))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(rows)))
        f.write(chunk(b"IEND", b""))


def base(x, y):
    return (x * 4, y * 5, 128, 255)


def changed(x, y):
    return (255, 0, 0, 255) if 20 <= x < 30 and 10 <= y < 15 else base(x, y)


out = sys.argv[1]
os.makedirs(out, exist_ok=True)
png(os.path.join(out, "a.png"), 64, 48, base)
png(os.path.join(out, "b.png"), 64, 48, changed)
