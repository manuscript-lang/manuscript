import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Unit!: ok(unit)

fn bad() Unit:
    value: Marker? := Marker(1)
    kept := value.ok_or_else(fn: "failure")
    again := value.ok_or_else(fn: "failure")
