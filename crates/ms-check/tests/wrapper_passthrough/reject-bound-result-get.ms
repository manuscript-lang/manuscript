import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

fn marker() Marker!Error: ok(Marker(1))

fn bad() Unit:
    let value = marker()
    let take = value.get
    let got = take(Marker(2))
    let _ = got.id
