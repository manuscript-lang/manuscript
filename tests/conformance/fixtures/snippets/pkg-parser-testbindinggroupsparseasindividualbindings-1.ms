# conform: tags=closures,diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/parser/group_test.go:11 TestBindingGroupsParseAsIndividualBindings
let (
    A = 1
    B: Int = A + 1
)

def main() -> Unit:
    var (
        a = 10
        b = lambda (x: Int) -> Int:
            return x + 1
    )
    let (
        c = 11
        d = "Hi"
    )
    a += 1
