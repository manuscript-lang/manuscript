import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

fn bad() Unit:
    let value: Marker!Int = ok(Marker(1))
    let kept = value.map_error(fn cause: cause + 1)
    let again = value.map_error(fn cause: cause + 1)
