fn fill(var xs: List[Int], count: Int) Unit:
    var i = 0
    while i < count:
        xs.append(i)
        i += 1

fn f() Int:
    var xs = [0]
    fill(var xs, 3)
    fill(var xs, 2)
    return xs.length()
