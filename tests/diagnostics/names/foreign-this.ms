// conform: tags=diagnostics,parser,tier-core
// conform: phase=check
// conform: origin=foreign-syntax diagnostics
fn f() Void {
	a := this
}
// expect-error: MS2001 5:10 unknown binding this; there is no 'this'; inside a method the receiver is 'self'
