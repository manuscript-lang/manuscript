# conform: tags=closures,diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/parser/group_test.go:11 TestBindingGroupsParseAsIndividualBindings
let (
    A = 1
    B: Int = A + 1
)

fn main() Unit:
    var (
        _a = 10
        _b = fn(x: Int) Int:
            return x + 1
    )
    let (
        _c = 11
        _d = "Hi"
    )
    _a += 1
