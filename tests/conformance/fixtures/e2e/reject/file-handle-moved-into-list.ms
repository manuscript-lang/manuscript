// conform: tags=testing,tier-io
// conform: phase=check
import OpenMode, open from "@std/os/fs.ms"

// A file handle has one owner: moving it into a list ends its use here.
fn reuse(path String) Int! {
	file := open(path, OpenMode.Read)?
	owners := [file]
	info := file.stat()?
	return ok(info.size + owners.length())
}
// expect-error: MS3000 8:16 `file` is moved here but used again at 9:13; a resource has one owner and cannot be cloned, so move it only at its last use, or pass it where it is only read
