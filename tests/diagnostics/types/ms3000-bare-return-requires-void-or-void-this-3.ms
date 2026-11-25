// conform: tags=diagnostics
// conform: phase=check
fn subtract(amount Int, deduction Int) Int => amount - deduction

fn run() Int {
	return
}
// expect-error: MS3000 6:5 bare return requires Void or Void!; this function returns Int, so write 'return <value>'
