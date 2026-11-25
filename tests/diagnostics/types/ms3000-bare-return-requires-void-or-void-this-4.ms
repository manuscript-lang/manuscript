// conform: tags=diagnostics
// conform: phase=check
fn f(first Int, second Int) Int => first

export fn main() Int {
	return
}
// expect-error: MS3000 6:5 bare return requires Void or Void!; this function returns Int, so write 'return <value>'
