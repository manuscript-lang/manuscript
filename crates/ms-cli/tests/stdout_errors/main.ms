import stdout, stderr from "@std/io/io.ms"
fn main() Int:
	var o = stdout()
	var e = stderr()
	if _x := o.write("hello\n"):
		_ := e.write("write ok\n")
	else:
		_ := e.write("write failed\n")
	r := o.flush()
	if r.is_ok():
		_ := e.write("flush ok\n")
	else:
		_ := e.write("flush failed: {r.err().message} {r.err().kind}\n")
	return 0
