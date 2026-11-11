// conform: tags=diagnostics
// conform: phase=check
type ListEntry[T]:
    payload: T
fn get() List[ListEntry[Int]]: [1].entries()
