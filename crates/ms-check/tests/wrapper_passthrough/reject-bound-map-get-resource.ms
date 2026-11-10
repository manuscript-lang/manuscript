import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

fn bad() Unit:
    var items = Map[Int, Marker]()
    items.add(1, Marker(1))
    read := items.get
    _ := read(1).is_some()
