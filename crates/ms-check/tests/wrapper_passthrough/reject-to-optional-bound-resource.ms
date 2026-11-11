import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Unit!: ok(unit)

fn bad() Unit:
    value: Marker!Int := ok(Marker(1))
    operation := value.to_optional
