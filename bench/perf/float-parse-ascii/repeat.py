import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location("base", pathlib.Path(__file__).with_name("driver.py"))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)

def expected(case, count):
    operation, dataset, unused = case
    if operation in ("parse_float", "float_special"):
        return count, "ok"
    if operation == "float_error":
        return count, "none"
    start = {"plain": 0, "wide": 9223372036800000000, "negative": -(1 << 63), "zero": 0}[dataset]
    values = [start + i for i in range(1000)]
    if operation == "parse_int":
        checksums = [abs(v) % 997 * (-1 if v < 0 else 1) for v in values]
    else:
        checksums = [len(str(v)) for v in values]
    whole, rest = divmod(count, 1000)
    return whole * sum(checksums) + sum(checksums[:rest]), str(values[(count - 1) % 1000])

base.expected = expected
base.CASES = [(op, dataset, 0) for op, datasets in [
    ("signed", ["plain", "wide", "negative"]),
    ("parse_int", ["plain", "wide", "negative"]),
    ("parse_float", ["plain", "scientific", "wide", "long"]),
    ("float_special", ["special"]),
    ("float_error", ["early", "late", "range", "range-long", "unicode"]),
] for dataset in datasets]

if __name__ == "__main__":
    base.main()
