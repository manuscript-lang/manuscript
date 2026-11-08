import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

impl Marker:
    fn identity() Marker: self

fn marker() Marker!Error: ok(Marker(1))

fn bad[T](value: T?) Unit:
    let recover = value.or_else
