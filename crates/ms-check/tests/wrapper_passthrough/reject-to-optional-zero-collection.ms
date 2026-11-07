import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

fn bad() Unit:
    let entry: Marker!Int = ok(Marker(1))
    let values = [entry]
    let kept = values.first().get().to_optional()
