import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Void!: ok()

fn Marker.identity() Marker: self

fn marker() Marker!Error: ok(Marker(1))

fn bad() Void:
    value: (fn() Int)? := fn: 1
    recover := value.or_else
