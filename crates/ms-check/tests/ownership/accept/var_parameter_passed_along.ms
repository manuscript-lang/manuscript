fn inner(var xs: List[Int]) Unit:
    xs.append(1)

fn outer(var xs: List[Int]) Unit:
    inner(var xs)
    inner(var xs)
