import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

fn bad() Int:
    items := [Marker(1)]
    got := items.get(0, Marker(2))
    return got.id
