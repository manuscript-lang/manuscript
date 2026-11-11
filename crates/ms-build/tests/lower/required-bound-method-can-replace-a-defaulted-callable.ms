// Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
type Offset:
    base: Int

fn Offset.original(value: Int = 7) Int: self.base + value

fn Offset.replacement(value: Int) Int: self.base + value + 1

export fn main() Int:
    offset := Offset(2)
    var callback = offset.original

    // Assigning a method value takes its receiver, as assigning a closure takes its captures.
    callback = offset.clone().replacement
    return callback(3)
