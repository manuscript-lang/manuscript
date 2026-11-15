import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Void!: ok(unit)

fn Marker.identity() Marker: self

fn marker() Marker!Error: ok(Marker(1))

fn bad() Void:
    recover := marker().or_else
