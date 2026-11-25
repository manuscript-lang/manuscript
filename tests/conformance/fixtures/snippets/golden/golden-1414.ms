// conform: tags=diagnostics
// conform: phase=check
import (
	Bytes from "@std/bytes.ms",
	stdout from "@std/io/io.ms",
)

test "bytes" {
	data := "x".to_bytes().with_value(index: 0, value: 255)
	_out := stdout().write_bytes(data: data)
}
