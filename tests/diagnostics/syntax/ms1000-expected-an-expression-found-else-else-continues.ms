// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
    if true { return else: return }
}
// expect-error: MS1000 4:22-4:26 expected an expression, found 'else'; 'else' continues an 'if' block: write it on the line of the closing '}' as '} else {'
