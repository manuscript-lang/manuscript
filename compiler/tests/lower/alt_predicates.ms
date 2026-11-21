fn a(x: Int?) Bool:
	return x.is_some()

fn b(x: Int?) Bool:
	return x.is_none()

fn c(x: Int!) Bool:
	return x.is_ok()

fn d(x: Int!) Bool:
	return x.is_error()

fn main() Int:
	if a(1) and b(none) and c(ok(1)) and d(error(Error("x"))): return 0
	return 1
