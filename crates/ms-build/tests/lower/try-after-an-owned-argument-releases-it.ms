# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.

fn make(n: Int) Result[String, Error]:
    if n > 0:
        return ok("x")

    return error(Error(message: "no"))

fn join(a: String, b: String) String:
    return a + b

fn both(n: Int) Result[String, Error]:
    return ok(join(a: try make(n), b: try make(n - 1)))

export fn main() Int:
    return 0
