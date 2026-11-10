// `.clone()` of a record that holds a function value is rejected in the ownership pass: a
// function value owns its captures and has one owner.
type Handler:
    run: fn(Int) Int

export fn main() Int:
    first := Handler(run: fn x: x * 2)
    again := first.clone()
    return again.run(2)
