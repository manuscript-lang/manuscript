# conform: tags=closures,formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_group_test.go:24 TestFormatKeepsBindingGroupsTogether
def helper() -> Int: 1

let (
    A = 1
    B: Int = A + 1
)

def main() -> Unit:
    let x = 1
    var (
        a = 10
        b = lambda (y: Int) -> Int:
            return y + 1
    )
    let (
        c = 11
        d = "Hi"
    )
    a += x + b(c)
