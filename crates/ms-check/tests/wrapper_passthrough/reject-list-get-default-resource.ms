import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Void!: ok(void)

fn bad() Int:
    items := [Marker(1)]
    got := items.get(0, Marker(2))
    return got.id
