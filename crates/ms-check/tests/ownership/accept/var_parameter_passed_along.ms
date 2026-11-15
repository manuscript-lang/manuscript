fn inner(var xs: List[Int]) Void:
    xs.append(1)

fn outer(var xs: List[Int]) Void:
    inner(var xs)
    inner(var xs)
