// conform: tags=diagnostics
// conform: phase=check
fn required(value: Int) Int: value
fn first() Unit:
    var callback: fn(Int) Int = from_callback(fn: fn(value: Int = 4): value)
    callback = required
    callback()