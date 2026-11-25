// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=foreign-syntax diagnostics
fn f() Bool {
	return False
}
// expect-error: MS2001 5:12 unknown binding False; booleans are lowercase: write true and false
// expect-fix: 5:12-5:17 "false"
