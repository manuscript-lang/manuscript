// conform: tags=closures,formatter,parser,strings,tier-core,try-result
// conform: phase=parse
// conform: origin=pkg/parser/result_type_test.go:15 TestResultTypeFollowsParametersWithoutArrow
fn f() Void:
    g := fn(x Int) Int!String => ok(x)
    return
