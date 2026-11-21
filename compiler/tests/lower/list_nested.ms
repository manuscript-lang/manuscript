fn grid() List[List[Int]]:
    return [[1, 2], [3]]

fn rows(g: List[List[Int]]) Int:
    var n = 0
    for r in g:
        n = n + r.length()
    return n

fn main() Int:
    g := grid()
    inner := [4, 5]
    h := [inner, [6]]
    return rows(g) + rows(h) + h.length()
