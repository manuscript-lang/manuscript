import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Void!: ok(void)

fn marker() Marker!Error: ok(Marker(1))

fn bad() Void:
    value := marker()
    take := value.get
    got := take(Marker(2))
    void got.id
