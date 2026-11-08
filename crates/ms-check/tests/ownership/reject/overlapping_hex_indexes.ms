fn both(var a: Int, var b: Int) Unit:
    a += 1
    b += 2

fn f(i: Int) Unit:
    var xs = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
    both(var xs[0xd], var xs[13])  // error: overlaps
    both(var xs[0xe], var xs[0xE])  // error: overlaps
    both(var xs[0xe], var xs[0b1110])  // error: overlaps
    both(var xs[0xd], var xs[i])  // error: overlaps
    both(var xs[0xe], var xs[-2])  // error: overlaps
