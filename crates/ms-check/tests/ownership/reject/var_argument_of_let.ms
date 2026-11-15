fn fill(var xs: List[Int]) Void:
    xs.append(1)

fn f() Void:
    xs := [1]
    fill(var xs)  // error: is an immutable binding
