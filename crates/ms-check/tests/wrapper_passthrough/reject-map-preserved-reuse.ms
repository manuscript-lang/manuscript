import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn move Marker.close() Void!: ok()

fn bad() Void:
    value: Int!Marker := error(Marker(1))
    kept := value.map(fn item: item + 1)
    again := value.map(fn item: item + 1)
