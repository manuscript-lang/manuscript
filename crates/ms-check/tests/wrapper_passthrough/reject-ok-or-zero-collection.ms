import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn move Marker.close() Void!: ok()

fn bad() Void:
    values := [Marker(1)]
    kept := values.first().ok_or(Error("missing"))
