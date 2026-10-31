fn keep(r: fn(Int) Int) List[fn(Int) Int]:
    var out = List[fn(Int) Int]()
    out.append(r)
    return out

fn f() Int:
    var a = [1, 2, 3]
    let b = keep(fn x: x + a.length())  # error: capture `a.clone()` to keep the original
    a.append(4)
    return b.length() + a.length()
