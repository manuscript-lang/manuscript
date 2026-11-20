// The operating system's wording of an error, as the Rust `ms` printed it (lower-case,
// without the number): `no such file or directory`. A kind with no entry keeps the
// message the standard library gave.
import expect_equal from "@std/test/test.ms"

fn wording(kind: String) String?:
	if kind == "ENOENT": return "no such file or directory"
	if kind == "EEXIST": return "file exists"
	if kind == "EACCES": return "permission denied"
	if kind == "EPERM": return "operation not permitted"
	if kind == "ENOTDIR": return "not a directory"
	if kind == "EISDIR": return "is a directory"
	if kind == "ENOTEMPTY": return "directory not empty"
	if kind == "EROFS": return "read-only file system"
	if kind == "ENOSPC": return "no space left on device"
	if kind == "ENAMETOOLONG": return "file name too long"
	if kind == "ELOOP": return "too many levels of symbolic links"
	if kind == "EINVAL": return "invalid argument"
	if kind == "EBUSY": return "device or resource busy"

	return none

export fn errno_text(cause: Error) String:
	if kind := cause.kind:
		if text := wording(kind): return text
	return cause.message.clone()

test "known kinds read like the system's text":
	expect_equal(errno_text(Error("x", kind: "ENOENT")), "no such file or directory")?
	expect_equal(errno_text(Error("x", kind: "EEXIST")), "file exists")?
	expect_equal(errno_text(Error("other", kind: "EIO")), "other")?
