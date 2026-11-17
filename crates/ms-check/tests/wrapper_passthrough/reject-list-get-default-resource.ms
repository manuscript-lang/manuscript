import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Void!: ok()

fn bad() Int:
    items := [Marker(1)]
    got := items.get_or(0, Marker(2))
    return got.id
