import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

fn bad() Int:
    let items = [Marker(1)]
    let got = items.get(0, Marker(2))
    return got.id
