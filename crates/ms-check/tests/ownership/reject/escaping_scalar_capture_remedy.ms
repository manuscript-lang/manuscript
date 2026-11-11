fn keep(r: fn(Int) Int) List[fn(Int) Int]:
    return [r]

fn f() Int:
    var a = 1
    b := keep(fn x: x + a)  // error: bind an immutable snapshot with `snapshot := a`
    a += 1
    return b.length() + a
