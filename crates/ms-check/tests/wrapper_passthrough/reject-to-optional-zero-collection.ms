import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Void!: ok(unit)

fn bad() Void:
    entry: Marker!Int := ok(Marker(1))
    values := [entry]
    kept := values.first().get().to_optional()
