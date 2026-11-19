fn both(var a: List[Int], var b: List[Int]) Void:
    a.append(1)
    b.append(2)

fn f() Void:
    var xs = [[1], [2]]
    both(xs[0], xs[0])  // error: overlaps
