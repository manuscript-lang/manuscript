import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

fn bad() Unit:
    let value: Marker!Int = ok(Marker(1))
    let kept = value.to_optional()
    let again = value.to_optional()
