// conform: tags=diagnostics
// conform: phase=check
fn helper() Int: 1
let (
    A = 1
    B: Int   = A+1
)
fn main() Unit:
    x := 1
    var (
        a = 10
        b = fn(x: Int) Int:
            return x + 1
    )
    let (
        c=11
        d = "Hi"
    )
    a += x + b(c)
