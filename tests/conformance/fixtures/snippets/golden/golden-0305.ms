// conform: tags=diagnostics
// conform: phase=check
fn broken(value: Missing) Void: return
fn empty[T]() T?: none
fn first() Void:
    value := empty()
