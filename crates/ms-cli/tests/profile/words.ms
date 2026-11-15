fn words(n: Int) Int:
    parts := "a b c d e f g h".split(" ")
    return parts.length() + n

fn main() Void:
    var total = 0
    for r in 0..20000:
        total += words(r)
    print(total)
