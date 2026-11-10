import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

fn bad() Unit:
    value: Marker!Int = ok(Marker(1))
    kept := value.map_error(fn cause: cause + 1)
    again := value.map_error(fn cause: cause + 1)
