// conform: tags=diagnostics
// conform: phase=check
fn pick[T](items List[T], keep fn(T) Bool) T? {
	return null
}

fn f() Int {
	nums := [1, 2]
	hit := pick(nums, fn(value Int) Bool => value > 1)
	return hit or 0
}
// expect-exit: 0
