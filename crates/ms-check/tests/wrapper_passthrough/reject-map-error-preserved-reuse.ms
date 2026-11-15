import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Void!: ok()

fn bad() Void:
    value: Marker!Int := ok(Marker(1))
    kept := value.map_error(fn cause: cause + 1)
    again := value.map_error(fn cause: cause + 1)
