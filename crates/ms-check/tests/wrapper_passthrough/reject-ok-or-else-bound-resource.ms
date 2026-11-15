import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Void!: ok()

fn bad() Void:
    value: Marker? := Marker(1)
    operation := value.ok_or_else[String]
