# conform: tags=closures,diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_group_test.go:6 TestFormatKeepsBindingGroupsTogether
fn helper() Int: 1

let (
    A = 1
    B: Int = A + 1
)

fn main() Unit:
    let x = 1
    var (
        a = 10
        b = fn(x: Int) Int:
            return x + 1
    )
    let (
        c = 11
        d = "Hi"
    )
    a += x + b(c)
