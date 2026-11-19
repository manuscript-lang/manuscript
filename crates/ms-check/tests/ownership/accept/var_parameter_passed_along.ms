fn inner(var xs: List[Int]) Void:
    xs.append(1)

fn outer(var xs: List[Int]) Void:
    inner(xs)
    inner(xs)
