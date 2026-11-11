// conform: tags=diagnostics
// conform: phase=check
fn count[T](values: List[T]) Int: return values.length()
fn probe() Int:
    values := [1, 2, 3]
    var sum = 0
    var i = 0
    while i < 1000:
        sum += count[Int](values)
        i += 1
    return sum
