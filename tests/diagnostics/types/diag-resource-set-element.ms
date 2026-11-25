// conform: tags=diagnostics,sets,tier-core
// conform: phase=check
import Closeable from "@std/core.ms"

type Door {
	name String
}

fn move Door.close() Void! => return ok()

fn main() Void {
	s := Set[Door]()
}
// expect-error: MS3021 12:10 Door does not satisfy Hashable; it is or holds a Closeable resource, which is closed once by its owner and cannot be a set element or map key; key on a plain value such as an Int id instead
