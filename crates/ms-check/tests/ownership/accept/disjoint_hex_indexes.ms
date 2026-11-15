fn both(var a: Int, var b: Int) Void:
    a += 1
    b += 2

fn f() Void:
    var xs = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
    both(var xs[0xd], var xs[0xe])
    both(var xs[0xD], var xs[0xE])
    both(var xs[0x0_d], var xs[0b1110])
