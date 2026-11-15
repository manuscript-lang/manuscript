fn both(var a: List[Int], var b: List[Int]) Void:
    a.append(1)
    b.append(2)

fn f() Void:
    var xs = [[1], [2]]
    both(var xs[0], var xs[1])
