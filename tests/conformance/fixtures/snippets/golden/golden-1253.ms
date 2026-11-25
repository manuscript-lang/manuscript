// conform: tags=diagnostics
// conform: phase=check
import Bytes from "@std/bytes.ms"

fn extract(data Bytes) List[UInt8] {
	bound fn() List[UInt8] := data.values
	return data.values()
}
// expect-error: MS3000 6:5 local binding bound is never read; remove it, use it, or name it with a leading '_' to ignore it
