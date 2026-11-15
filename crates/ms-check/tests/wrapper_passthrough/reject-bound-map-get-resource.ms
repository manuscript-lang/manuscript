import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Void!: ok(unit)

fn bad() Void:
    var items = Map[Int, Marker]()
    items.add(1, Marker(1))
    read := items.get
    _ := read(1).is_some()
