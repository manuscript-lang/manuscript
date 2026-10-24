def inner(var xs: List[Int]) -> Unit:
    xs.append(1)

def outer(var xs: List[Int]) -> Unit:
    inner(var xs)
    inner(var xs)
