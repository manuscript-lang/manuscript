fn check(n: Int) Void!:
	if n < 0: return error(Error("negative"))
	return ok(void)

fn quiet(n: Int) Void!:
	if n < 0: return error(Error("negative"))
	return ok()

fn main() Int:
	r := check(1)
	if r.is_error(): return 1

	q := quiet(2)
	if q.is_error(): return 2

	return 0
