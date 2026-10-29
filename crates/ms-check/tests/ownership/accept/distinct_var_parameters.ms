fn both(var a: List[Int], var b: List[Int]) Unit:
    a.append(1)
    b.append(2)

fn f() Int:
    var xs = [1]
    var ys = [2]
    both(var xs, var ys)
    return xs.length() + ys.length()
