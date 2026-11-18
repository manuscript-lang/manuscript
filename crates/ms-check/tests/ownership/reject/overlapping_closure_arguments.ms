fn apply(f: fn() Void, g: fn() Void) Void:
    f()
    g()

fn main() Int:
    var n = 0
    apply(fn: n += 1, fn: n += 2)  // error: the closure at 7:11 of `apply` is moved or changed in place but overlaps the closure at 7:23
    return n
