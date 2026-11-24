// conform: tags=diagnostics
// conform: phase=check
fn broken(value Missing) Void => return
fn empty[T]() T? => null
fn first() Void:
    value := empty()
