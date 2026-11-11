fn keep(r: fn(Int) Int) List[fn(Int) Int]:
    return [r]

fn f() Int:
    var a = 1
    snapshot := a
    b := keep(fn x: x + snapshot)
    a += 1
    return b.length() + a
