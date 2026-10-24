def fill(var xs: List[Int]) -> Unit:
    xs.append(1)

def f() -> Unit:
    let xs = [1]
    fill(var xs)  # error: declared with let
