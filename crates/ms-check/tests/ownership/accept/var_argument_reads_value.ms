fn grow(var xs: List[Int], count: Int) Void:
    xs.append(count)

fn f() Void:
    var xs = [1]
    grow(var xs, xs.length())
