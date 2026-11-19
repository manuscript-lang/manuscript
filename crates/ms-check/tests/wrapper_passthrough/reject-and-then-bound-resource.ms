import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn move Marker.close() Void!: ok()

fn bad() Void:
    value: Int!Marker := error(Marker(1))
    operation := value.and_then[Int]
