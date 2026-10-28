import Closeable from "@std/core.ms"

type Resource:
    value: Int

impl Closeable for Resource:
    var fn close() Unit: return unit

fn main() Unit:
    wi
