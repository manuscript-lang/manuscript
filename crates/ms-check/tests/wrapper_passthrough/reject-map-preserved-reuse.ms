import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Unit!: ok(unit)

fn bad() Unit:
    value: Int!Marker := error(Marker(1))
    kept := value.map(fn item: item + 1)
    again := value.map(fn item: item + 1)
