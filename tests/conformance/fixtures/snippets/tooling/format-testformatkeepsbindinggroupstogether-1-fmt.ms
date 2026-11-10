// conform: tags=closures,formatter,mutation,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/format/format_group_test.go:6 TestFormatKeepsBindingGroupsTogether
fn helper() Int: 1

A := 1
B: Int = A + 1

fn main() Unit:
    x := 1
    var (
        _a = 10
        b = fn(y: Int) Int:
            return y + 1
    )
    c := 11
    _d := "Hi"
    _a += x + b(c)
