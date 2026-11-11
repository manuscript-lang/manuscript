// conform: tags=diagnostics
// conform: phase=check
import stdout from "@std/io/io.ms"
import Bytes from "@std/bytes.ms"

test "bytes":
    data := "x".to_bytes().with_value(index: 0, value: 255)
    _out := stdout().write_bytes(data: data)
