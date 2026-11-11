// conform: tags=diagnostics
// conform: phase=check
fn collect[T, U](items: List[T], step: fn(T) Result[List[U], MissingError]) Result[List[U], MissingError]:
    return step(items.get(0))
fn first() Unit:
    result := collect(items: [1, 2], step: fn(value: Int) Result[List[Int], MissingError]: ok([value]))
    unrelated: Int := "wrong"
