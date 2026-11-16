import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Void!: ok()

fn bad() Void:
    value: Marker!Int := ok(Marker(1))
    operation := value.to_optional
