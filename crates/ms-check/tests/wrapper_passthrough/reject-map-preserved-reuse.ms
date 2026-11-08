import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

fn bad() Unit:
    let value: Int!Marker = error(Marker(1))
    let kept = value.map(fn item: item + 1)
    let again = value.map(fn item: item + 1)
