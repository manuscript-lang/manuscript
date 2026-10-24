def f(var xs: List[Int]) -> Unit:
    for x in xs:
        xs.append(x)  # error: borrows it
