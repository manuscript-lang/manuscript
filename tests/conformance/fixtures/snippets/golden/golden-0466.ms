// conform: tags=diagnostics
// conform: phase=check
enum CollectionError:
    OutOfRange
fn get() Result[List[Int], CollectionError]: [1].slice(0, 1)
