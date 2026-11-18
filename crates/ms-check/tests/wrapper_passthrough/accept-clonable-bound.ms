import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Void!: ok()

fn Marker.identity() Marker: self

fn marker() Marker!Error: ok(Marker(1))

fn generic[T: Clonable](value: T?) T?:
    recover := value.or_else
    return recover(fn: none)

fn data() Int:
    value: String? := "payload"
    recover := value.or_else
    first := recover(fn: none)
    second := recover(fn: none)
    return first.get().length() + second.get().length() + value.get().length()
