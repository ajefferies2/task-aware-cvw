#!/usr/bin/env python3
"""Convert a little-endian flat RV32 binary to a word-addressed $readmemh file."""
import argparse
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("binary", type=Path)
p.add_argument("output", type=Path)
a = p.parse_args()
data = a.binary.read_bytes()
if len(data) > 0xFF00:
    p.error("binary overlaps reserved runtime mailbox/stack boundary")
data += bytes((-len(data)) % 4)
a.output.write_text("".join(f"{int.from_bytes(data[i:i+4], 'little'):08x}\n"
                          for i in range(0, len(data), 4)))
