fn f(var xs: List[Int]) Void:
    for x in xs:
        xs.append(x)  // error: borrows it
