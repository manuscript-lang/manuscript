import Closeable from "@std/core.ms"

type Resource:
    id: Int

impl Closeable for Resource:
    var fn close() Unit!:
        return ok(unit)

fn identity(r: Resource) Resource:
    return r

export fn main() Int:
    f := identity
    r := Resource(7)
    out := f(r)
    return out.id - 7
