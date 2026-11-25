// conform: tags=diagnostics
// conform: phase=check
type Point {
	x Int
}

fn f() Int {
	Point = 2
	return 0
}
// expect-error: MS3000 8:5 cannot assign to type Point; assignment targets are 'var' bindings and type fields
