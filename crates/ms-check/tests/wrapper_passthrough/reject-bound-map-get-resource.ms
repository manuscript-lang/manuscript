import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn move Marker.close() Void!: ok()

fn bad() Void:
    var items = Map[Int, Marker]()
    items.add(1, Marker(1))
    read := items.get
    void read(1).is_some()
