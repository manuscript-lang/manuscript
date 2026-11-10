import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

fn bad() Unit:
    value: Int!Marker = error(Marker(1))
    kept := value.and_then(fn item: ok(item + 1))
    again := value.and_then(fn item: ok(item + 1))
