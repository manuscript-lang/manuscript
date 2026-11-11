import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Unit!: ok(unit)

fn marker() Marker!Error: ok(Marker(1))

fn bad() Unit:
    value := marker()
    take := value.get
    got := take(Marker(2))
    _ := got.id
