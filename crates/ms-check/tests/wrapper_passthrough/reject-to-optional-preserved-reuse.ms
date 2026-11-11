import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

fn bad() Unit:
    value: Marker!Int := ok(Marker(1))
    kept := value.to_optional()
    again := value.to_optional()
