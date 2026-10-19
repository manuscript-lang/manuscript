fn fill(var xs: List[Int]) Unit:
    xs.append(1)

fn f() Int:
    var xs = [0]
    fill(xs)  # error: is declared var
    return xs.length()
