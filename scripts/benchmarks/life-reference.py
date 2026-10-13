#!/usr/bin/env python3
"""Independent checksum oracle for life.ms (not a performance comparator)."""
size = 128
cells = [int((i * 17 + i // size * 13) % 7 < 3) for i in range(size * size)]
for _ in range(50):
    next_cells = [0] * (size * size)
    for y in range(size):
        for x in range(size):
            neighbors = sum(
                cells[((y + dy) % size) * size + (x + dx) % size]
                for dy in (-1, 0, 1)
                for dx in (-1, 0, 1)
                if dx != 0 or dy != 0
            )
            next_cells[y * size + x] = int(neighbors == 3 or (neighbors == 2 and cells[y * size + x] == 1))
    cells = next_cells
assert sum(cells) == 3914
print(sum(cells))
