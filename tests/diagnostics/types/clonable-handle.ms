// conform: tags=testing,tier-io
// conform: phase=check
import FileHandle from "@std/os/fs.ms"

fn twice[T Clonable](value T) List[T] {
	return [value.clone(), value]
}

fn keep(handle FileHandle) Int {
	return twice(handle).length()
}

export fn main() Int {
	return 0
}
// expect-error: MS3000 10:12 FileHandle does not satisfy Clonable; it is or holds a Closeable resource, which has one owner and closes once, so it cannot be cloned; move it, or use it in place
