fn keep(r: fn(Int) Int) List[fn(Int) Int]:
    var out = List[fn(Int) Int]()
    out.append(r)
    return out

fn f() Int:
    a := [1, 2, 3]
    b := keep(fn x: x + a.length())
    return b.length()
