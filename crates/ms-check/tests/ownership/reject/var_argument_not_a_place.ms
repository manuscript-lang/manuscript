fn fill(var xs: List[Int]) Void:
    xs.append(1)

fn f() Void:
    fill(var [1])  // error: must be a variable
