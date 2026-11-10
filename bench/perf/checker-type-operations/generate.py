"""Generate source workloads without requiring a pre-existing Manuscript binary."""

import argparse
from pathlib import Path


def shared(depth, operation):
    source = """type Pair[A, B]:
    value: Int

fn double[T: Clonable](_value: T) Pair[T, T]:
    return Pair[T, T](0)

impl Pair[A, B]:
    fn with_second[C](_value: C) Pair[A, C]:
        return Pair[A, C](self.value)

fn callback[T](_value: T) fn(T) Int:
    return fn(_other: T) Int: 0

export fn main() Int:
    v0 := 1
"""
    for i in range(1, depth + 1):
        source += f"    v{i} := double(v{i - 1})\n"
    value = f"v{depth}"
    if operation == "match":
        source += f"    chosen := match true:\n        true: {value}\n        false: {value}\n    return chosen.value\n"
    elif operation == "callback":
        source += f"    cb := callback({value})\n    return cb({value})\n"
    elif operation == "method":
        source += f"    changed := {value}.with_second(1)\n    return changed.value\n"
    else:
        raise ValueError(operation)
    return source


def ordinary(count, generic):
    if generic:
        source = """type Box[T]:
    value: T

fn read[T](box: Box[T]) T:
    return box.value

"""
        arg = "box: Box[Int]"
        body = "read(box)"
    else:
        source = "type Box:\n    value: Int\n\n"
        arg = "box: Box"
        body = "box.value"
    for i in range(count):
        source += f"fn access_{i}({arg}) Int: {body}\n"
    source += "\nexport fn main() Int: 0\n"
    return source


def unique_method(depth, calls):
    source = shared(depth, "method").replace("Pair[T, T]", "Pair[T, Int]")
    source = source[:source.index("    changed :=")]
    source += "    var total = 0\n"
    for i in range(calls):
        source += f"    total += v{depth}.with_second({i}).value\n"
    return source + "    return total\n"


def callback_methods(count):
    source = """type Box[T]:
    value: T

impl Box[T]:
    fn convert[U](f: fn(T) U) U:
        return f(self.value)

"""
    for i in range(count):
        source += f"fn access_{i}(box: Box[Int]) Int: box.convert(fn value: value + 1)\n"
    return source + "\nexport fn main() Int: 0\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for operation in ("match", "callback", "method"):
        for depth in (4, 8, 12, 16, 20, 24, 28):
            (args.output / f"shared-{operation}-{depth}.ms").write_text(shared(depth, operation))
    for generic in (False, True):
        for count in (1, 16, 250, 500, 1000):
            (args.output / f"ordinary-{'generic' if generic else 'concrete'}-{count}.ms").write_text(ordinary(count, generic))
    for depth in (4, 16, 64, 128):
        for calls in (1, 16, 64):
            (args.output / f"unique-method-{depth}-{calls}.ms").write_text(unique_method(depth, calls))
    for count in (1, 16, 250, 500, 1000):
        (args.output / f"callback-methods-{count}.ms").write_text(callback_methods(count))
    for count in (1, 16, 250, 1000):
        (args.output / f"rejected-generic-{count}.ms").write_text(ordinary(count, True) + '\nfn rejected() Int: "wrong"\n')


if __name__ == "__main__":
    main()
