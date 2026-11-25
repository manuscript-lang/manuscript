// conform: tags=diagnostics
// conform: phase=check
fn helper() Int {
	return 1
}

fn f() Int {
	helper = 2
	return 0
}
// expect-error: MS3000 8:5 cannot assign to function helper; assignment targets are 'var' bindings and type fields
