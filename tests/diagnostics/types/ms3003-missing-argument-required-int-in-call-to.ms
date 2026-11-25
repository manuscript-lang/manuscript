// conform: tags=diagnostics
// conform: phase=check
type Options {
	required Int
	count Int = 1
}

fn f() Options => return Options()
// expect-error: MS3003 8:26 missing argument required: Int in call to Options; add 'required: <Int>'
