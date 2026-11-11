import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

impl Marker:
    fn identity() Marker: self

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

fn resource_error() Int:
    value: Int!Marker := error(Marker(1))
    recovered := value.or_else(fn cause: ok(cause.id))
    if value.is_error(): return recovered.get()

    return 0

fn bound_resource_error() Int:
    value: Int!Marker := error(Marker(1))
    recover := value.or_else
    first := recover(fn cause: ok(cause.id))
    second := recover(fn cause: ok(cause.id + 1))
    if value.is_error(): return first.get() + second.get()

    return 0
