import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Unit!: ok(unit)

fn bad() Unit:
    var items = [Marker(1)]
    drop := items.remove
    drop(0)
