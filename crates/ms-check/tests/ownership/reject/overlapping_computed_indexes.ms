fn both(var a: List[Int], var b: List[Int]) Unit:
    a.append(1)
    b.append(2)

fn f(i: Int) Unit:
    var xs = [[1], [2]]
    both(var xs[0], var xs[i])  # error: overlaps
