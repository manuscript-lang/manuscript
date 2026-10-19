fn size(xs: List[Int]) Int:
    return xs.length()

fn f() Int:
    var xs = [0]
    return size(var xs)  # error: does not change
