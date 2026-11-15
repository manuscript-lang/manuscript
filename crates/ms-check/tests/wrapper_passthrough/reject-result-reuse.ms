import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Void!: ok(void)

fn Marker.identity() Marker: self

fn marker() Marker!Error: ok(Marker(1))

fn bad() Int:
    value := marker()
    kept := value.or_else(fn cause: error(cause))
    return value.get().id + kept.get().id
