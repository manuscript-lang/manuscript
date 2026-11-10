import Closeable from "@std/core.ms"

type Res:
    id: Int

impl Closeable for Res:
    var fn close() Unit!:
        return ok(unit)

// An unconstrained element may be a resource, so a copy could be closed twice.
fn copy[T](items: List[T]) List[T]:
    return items.clone()  // error: cannot be cloned

fn main() Int:
    return copy([Res(1)]).length()
