# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
def original(value: Int = 7) -> Int: value + 1
def replacement(value: Int) -> Int: value + 2
def choose[T](left: T, right: T) -> T: right
export def main() -> Int:
    return choose(original, replacement)(3)
