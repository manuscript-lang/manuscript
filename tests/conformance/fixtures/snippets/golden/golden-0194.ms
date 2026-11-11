// conform: tags=diagnostics
// conform: phase=check
fn from_callback[T](factory: fn() T) T: factory()
fn first() Unit:
    callback: fn(Int) Int := from_callback(fn: fn(value: Int = 4): value)
