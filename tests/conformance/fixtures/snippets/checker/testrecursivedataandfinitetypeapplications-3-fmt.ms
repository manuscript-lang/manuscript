// conform: tags=alternatives,formatter,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:20 TestRecursiveDataAndFiniteTypeApplications
enum A:
    End
    Next(value: B)

type B:
    a: A
