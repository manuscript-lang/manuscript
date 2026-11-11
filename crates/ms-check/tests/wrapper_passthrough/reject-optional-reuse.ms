import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Unit!: ok(unit)

fn Marker.identity() Marker: self

fn marker() Marker!Error: ok(Marker(1))

fn bad() Int:
    value: Marker? := Marker(1)
    kept := value.or_else(fn: none)
    return value.get().id + kept.get().id
