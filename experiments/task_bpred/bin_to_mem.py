#!/usr/bin/env python3
"""Convert a little-endian flat RV32 binary to a word-addressed $readmemh file."""
import argparse
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("binary", type=Path)
p.add_argument("output", type=Path)
p.add_argument("--ram-bytes", type=int, default=65536)
a = p.parse_args()
data = a.binary.read_bytes()
if a.ram_bytes < 65536 or a.ram_bytes & (a.ram_bytes - 1):
    p.error("RAM size must be a power of two of at least 65536 bytes")
if len(data) > min(65536, a.ram_bytes - 4096):
    p.error("binary exceeds the 64 KiB IROM or overlaps the results mailbox")
data += bytes((-len(data)) % 4)
a.output.write_text("".join(f"{int.from_bytes(data[i:i+4], 'little'):08x}\n"
                          for i in range(0, len(data), 4)))
