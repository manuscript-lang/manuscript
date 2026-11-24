// conform: tags=diagnostics
// conform: phase=check
// A parameter the body returns is the callee's to own, so the signature says `move`; the compiler does not read the
// body to find out, and a caller reading only the signature knows its argument stays its own.
import FileHandle from "@std/os/fs.ms"

fn pass(move file FileHandle) FileHandle:
	return file
