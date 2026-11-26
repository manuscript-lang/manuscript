// conform: tags=diagnostics,tier-core
// conform: phase=check
fn show(xs List[String]) Void {
	print(f"{xs.join(\", \")}")
}
// expect-error: MS1000 4:13 a backslash cannot appear in the interpolated expression ('{' starts an interpolation in f"..." text; write \\{ and \\} for literal braces, or drop the f)
