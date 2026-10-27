# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "fn @run"

type Reader:
    pos: Int

def peek(reader: Reader) -> String:
    return "a"

def advance(var reader: Reader) -> String:
    reader.pos += 1
    return "a"

def run(var reader: Reader) -> Int:
    var count = 0
    while True:
        var key = ""
        while reader.pos < 3 and "abc".contains(peek(reader)):
            key = key.concat(advance(var reader))
        if key == "": return 9
        count += 1
        if count > 2: return count
    return 0

export def main() -> Int:
    var reader = Reader(pos: 0)
    return run(var reader)
