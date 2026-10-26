# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
type Offset:
    base: Int
impl Offset:
    def original(value: Int = 7) -> Int: self.base + value
    def replacement(value: Int) -> Int: self.base + value + 1
export def main() -> Int:
    let offset = Offset(2)
    var callback = offset.original
    callback = offset.replacement
    return callback(3)
