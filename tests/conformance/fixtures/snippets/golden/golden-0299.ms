// conform: tags=diagnostics
// conform: phase=check
fn boxed(value SetBuilder[Int]) Void => return
// expect-error: MS2001 3:16 unknown type SetBuilder; declare it with 'type SetBuilder:' / 'enum SetBuilder:' / 'interface SetBuilder:', declare it as a type parameter, or import it
