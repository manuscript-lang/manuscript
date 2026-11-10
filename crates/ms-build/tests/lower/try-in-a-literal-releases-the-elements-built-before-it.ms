// Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.

fn bad() Result[String, Error]:
    return error(Error("no"))

fn list() Result[Int, Error]:
    xs := ["a", try bad(), "c"]
    return ok(xs.length())

fn nested() Result[Int, Error]:
    xs := [["a"], ["b", try bad()]]
    return ok(xs.length())

fn map_value() Result[Int, Error]:
    m := {"a": "x", "b": try bad()}
    return ok(m.length())

fn map_key() Result[Int, Error]:
    m := {"a": "x", (try bad()): "y"}
    return ok(m.length())

fn main() Unit:
    _a := list()
    _b := nested()
    _c := map_value()
    _d := map_key()
