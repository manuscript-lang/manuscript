def both(var a: List[Int], var b: List[Int]) -> Unit:
    a.append(1)
    b.append(2)

def f() -> Unit:
    var xs = [1]
    both(var xs, var xs)  # error: overlaps
