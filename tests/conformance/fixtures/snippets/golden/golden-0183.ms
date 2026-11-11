// conform: tags=diagnostics
// conform: phase=check
type Callback:
    value: fn(Int) Int
fn example() Unit:
    callback := Callback(fn value: value + 1)
