fn both(var a: List[Int], var b: List[Int]) Void:
    a.append(1)
    b.append(2)

fn f() Void:
    var xs = [1]
    both(xs, xs)  // error: overlaps
