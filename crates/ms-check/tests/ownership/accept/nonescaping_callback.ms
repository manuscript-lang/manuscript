def f(xs: List[Int]) -> List[Int]:
    var extra = [10]
    xs.for_each(
        lambda (v: Int) -> Unit:
            extra.append(v)
    )
    return xs.map(lambda (v: Int) -> Int: v + extra.length())
