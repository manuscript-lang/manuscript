// conform: tags=diagnostics
// conform: phase=check
import Bytes from "@std/bytes.ms"

fn make() Bytes {
	return
}
// expect-error: MS3000 6:5 bare return requires Void or Void!; this function returns Bytes, so write 'return <value>'
