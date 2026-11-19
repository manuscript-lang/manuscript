fn both(var a: Int, var b: Int) Void:
    a += 1
    b += 2

fn f() Void:
    var xs = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
    both(xs[0xd], xs[0xe])
    both(xs[0xD], xs[0xE])
    both(xs[0x0_d], xs[0b1110])
