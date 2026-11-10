import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

impl Marker:
    fn identity() Marker: self

fn marker() Marker!Error: ok(Marker(1))

fn bad() Int:
    values := [Marker(1)]
    kept := values.first().or_else(fn: none)
    return kept.get().id
