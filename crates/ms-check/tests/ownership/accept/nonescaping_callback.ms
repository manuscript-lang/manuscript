fn f(xs: List[Int]) List[Int]:
    var extra = [10]
    xs.for_each(
        fn(v: Int) Unit:
            extra.append(v)
    )
    return xs.map(fn(v: Int) Int: v + extra.length())
