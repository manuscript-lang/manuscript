import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

fn bad() Unit:
    let value: Marker? = Marker(1)
    let kept = value.ok_or("failure")
    let again = value.ok_or("failure")
