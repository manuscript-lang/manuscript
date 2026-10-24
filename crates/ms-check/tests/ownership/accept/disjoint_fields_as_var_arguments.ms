type Pair:
    left: List[Int]
    right: List[Int]

def fill(var xs: List[Int]) -> Unit:
    xs.append(1)

def f() -> Int:
    var p = Pair(left: [0], right: [0])
    fill(var p.left)
    fill(var p.right)
    return p.left.length() + p.right.length()
