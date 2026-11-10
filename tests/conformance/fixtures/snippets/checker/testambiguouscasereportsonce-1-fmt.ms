// conform: tags=alternatives,formatter,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/ambiguous_case_test.go:16 TestAmbiguousCaseReportsOnce
enum A:
    X

enum B:
    X

fn f() Int:
    a := X
    return 1
