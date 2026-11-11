// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=type-sets
type Number = Int | Float

fn total[T: Number](values: List[T]) T:
    var sum: T = 0
    for v in values:
        sum += v
    return sum

fn main() Unit:
    print(total(["a"]))
