#!/usr/bin/env python3
"""Longer paired controls for apparent regressions in the full measurement."""

import measure


if __name__ == "__main__":
    measure.CASES = [
        ("int", 100000, 1, 500),
        ("string", 100000, 32, 300),
        ("string", 100000, 100000, 20),
        ("difference", 1024, 1024, 10000),
        ("symmetric_difference", 1024, 1024, 5000),
    ]
    measure.main()
