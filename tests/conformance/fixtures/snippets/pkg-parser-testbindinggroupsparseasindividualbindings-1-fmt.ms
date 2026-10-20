# conform: tags=closures,formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/group_test.go:11 TestBindingGroupsParseAsIndividualBindings
let (
    A = 1
    B: Int = A + 1
)

fn main() Unit:
    var (
        a = 10
        b = fn(x: Int) Int:
            return x + 1
    )
    let (
        c = 11
        d = "Hi"
    )
    a += 1
