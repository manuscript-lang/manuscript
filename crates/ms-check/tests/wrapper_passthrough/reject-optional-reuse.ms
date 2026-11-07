import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

impl Marker:
    fn identity() Marker: self

fn marker() Marker!Error: ok(Marker(1))

fn bad() Int:
    let value: Marker? = Marker(1)
    let kept = value.or_else(fn: none)
    return value.get().id + kept.get().id
