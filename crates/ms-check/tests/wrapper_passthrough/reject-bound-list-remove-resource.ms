import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn move Marker.close() Void!: ok()

fn bad() Void:
    var items = [Marker(1)]
    drop := items.remove
    drop(0)
