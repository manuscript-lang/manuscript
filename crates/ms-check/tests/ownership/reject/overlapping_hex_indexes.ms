fn both(var a: Int, var b: Int) Void:
    a += 1
    b += 2

fn f(i: Int) Void:
    var xs = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
    both(xs[0xd], xs[13])  // error: overlaps
    both(xs[0xe], xs[0xE])  // error: overlaps
    both(xs[0xe], xs[0b1110])  // error: overlaps
    both(xs[0xd], xs[i])  // error: overlaps
    both(xs[0xe], xs[-2])  // error: overlaps
