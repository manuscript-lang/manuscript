import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Void!: ok()

fn bad() Void:
    values := [Marker(1)]
    kept := values.first().ok_or()
