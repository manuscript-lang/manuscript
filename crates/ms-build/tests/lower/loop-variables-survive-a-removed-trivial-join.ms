# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "fn @run"

type Reader:
    pos: Int

fn peek(reader: Reader) String:
    return "a"

fn advance(var reader: Reader) String:
    reader.pos += 1
    return "a"

fn run(var reader: Reader) Int:
    var count = 0

    while true:
        var key = ""
        while reader.pos < 3 and "abc".contains(peek(reader)):
            key = key.concat(advance(var reader))
        if key == "": return 9

        count += 1
        if count > 2: return count

    return 0

export fn main() Int:
    var reader = Reader(pos: 0)
    return run(var reader)
