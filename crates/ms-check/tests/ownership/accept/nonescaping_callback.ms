fn f(xs: List[Int]) List[Int]:
    let extra = [10]
    xs.for_each(fn(v: Int) Unit:
        extra.length()
    )
    return xs.map(fn(v: Int) Int: v + extra.length())
