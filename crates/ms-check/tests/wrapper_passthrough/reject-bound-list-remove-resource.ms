import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Void!: ok(unit)

fn bad() Void:
    var items = [Marker(1)]
    drop := items.remove
    drop(0)
