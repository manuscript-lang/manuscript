#!/usr/bin/env python3
"""Longer full-scan controls, using the same checked paired harness."""
import measure

measure.CASES = [(kind, size, pattern, repeats) for kind in ("subset", "superset", "disjoint")
                 for size, repeats in [(1024, 40000), (65536, 600)]
                 for pattern in ("true", "late")]

if __name__ == "__main__":
    measure.main()
