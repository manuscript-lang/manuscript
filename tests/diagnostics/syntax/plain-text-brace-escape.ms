// conform: tags=diagnostics,tier-core
// conform: phase=check
fn show() Void {
	print("\{ \}")
}
// expect-error: MS1000 4:12 braces are plain characters in "..." text, so write { and } without a backslash; only f"..." text interpolates and escapes them
