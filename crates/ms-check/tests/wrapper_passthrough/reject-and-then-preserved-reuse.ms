import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn move Marker.close() Void!: ok()

fn bad() Void:
    value: Int!Marker := error(Marker(1))
    kept := value.and_then(fn item: ok(item + 1))
    again := value.and_then(fn item: ok(item + 1))
