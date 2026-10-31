"""Longer rejected-candidate/A-A controls; use measure.py's argument order."""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("sequence_measure", Path(__file__).with_name("measure.py"))
measure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(measure)


def cases():
    for operation, size in (("priority", 1), ("priority", 8), ("priority", 128),
                            ("queue", 8192), ("queue", 100000), ("deque", 8192)):
        yield operation, size, "random", max(20, 10000000 // size)


measure.cases = cases
measure.main()
