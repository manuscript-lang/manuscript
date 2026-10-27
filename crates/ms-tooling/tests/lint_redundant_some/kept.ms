def n(x: Optional[Optional[Int]]) -> Int:
    return 1

export def main() -> Int:
    let keep = some(5)
    return n(some(none)) + n(some(some(1))) + keep.get(0)
