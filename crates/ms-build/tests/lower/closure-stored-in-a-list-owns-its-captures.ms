# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# A closure stored in a list owns what it captures; the verifier rejects a borrowing closure that is stored.
# expect-mir: "fn @closure_keeps"
fn closure_keeps(text: String) Int:
    var fs: List[fn() Int] = []
    for p in text.split(","):
        fs.append(fn() Int: return p.length())

    var t = 0
    for f in fs:
        t += f()
    return t

export fn main() Int:
    return closure_keeps("x,yyyy,zz")
