# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "fn @pad"

def pad(x: Int, by: Int = 2) -> Int:
    return x + by

export def main() -> Int:
    return pad(1)
