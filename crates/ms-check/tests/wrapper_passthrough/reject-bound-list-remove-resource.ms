import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

fn bad() Unit:
    var items = [Marker(1)]
    let drop = items.remove
    drop(0)
