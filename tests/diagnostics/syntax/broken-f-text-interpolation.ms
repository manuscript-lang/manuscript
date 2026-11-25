// conform: tags=diagnostics,tier-core
// conform: phase=check
fn show(total Int) Void {
	print(f"{total +}")
}
// expect-error: MS1000 4:21-4:21 expected an expression, found end of line; write a value, name, call, or literal here ('{' at column 13 starts an interpolation in f"..." text; write \\{ and \\} for literal braces, or drop the f)
