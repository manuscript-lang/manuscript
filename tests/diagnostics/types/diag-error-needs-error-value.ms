// conform: tags=diagnostics,tier-core
// conform: phase=check
fn f(x Int) Int! {
	if x < 0 {
		return error("negative")
	}
	return ok(x)
}

export fn main() Int {
	print(f(1).is_error())
	return 0
}
// expect-error: MS3001 5:22 expected Error, found String (in argument 'cause' of error); String does not convert to Error implicitly; make the error with Error("message"), e.g. error(Error("message"))
// expect-fix: 5:22-5:32 "Error(\"negative\")"
