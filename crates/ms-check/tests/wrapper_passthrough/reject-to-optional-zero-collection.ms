import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Unit!: ok(unit)

fn bad() Unit:
    entry: Marker!Int := ok(Marker(1))
    values := [entry]
    kept := values.first().get().to_optional()
