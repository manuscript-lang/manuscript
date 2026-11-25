// conform: tags=diagnostics
// conform: phase=check
fn f(transform fn(value) Int) Void => return
// expect-error: MS2001 3:19 unknown type value; declare it with 'type value:' / 'enum value:' / 'interface value:', declare it as a type parameter, or import it
