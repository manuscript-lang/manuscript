// conform: tags=testing,tier-io
// conform: phase=check
import FileHandle from "@std/os/fs.ms"

fn twice[T: Clonable](value: T) List[T]:
	return [value.clone(), value]

fn keep(handle: FileHandle) Int:
	return twice(handle).length()

export fn main() Int:
	return 0
