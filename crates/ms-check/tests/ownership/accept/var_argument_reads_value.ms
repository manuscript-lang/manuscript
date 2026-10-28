fn grow(var xs: List[Int], count: Int) Unit:
    xs.append(count)

fn f() Unit:
    var xs = [1]
    grow(var xs, xs.length())
