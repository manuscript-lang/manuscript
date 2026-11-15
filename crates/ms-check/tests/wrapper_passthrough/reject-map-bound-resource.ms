import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Void!: ok()

fn bad() Void:
    value: Int!Marker := error(Marker(1))
    operation := value.map[Int]
