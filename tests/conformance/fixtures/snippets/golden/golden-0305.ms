// conform: tags=diagnostics
// conform: phase=check
fn broken(value: Missing) Unit: return
fn empty[T]() T?: none
fn first() Unit:
    value := empty()
