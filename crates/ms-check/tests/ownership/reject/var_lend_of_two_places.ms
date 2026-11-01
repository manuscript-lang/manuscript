fn pick(a: List[Int], b: List[Int], left: Bool) List[Int]:
    if left: return a
    return b

fn change(var a: List[Int], var b: List[Int]) Unit:
    var xs = pick(a, b, true)  # error: the result is a reference into more than one place
    xs.append(1)
