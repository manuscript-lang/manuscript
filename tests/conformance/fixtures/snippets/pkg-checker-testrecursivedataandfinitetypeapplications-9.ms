# conform: tags=diagnostics,optional,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:26 TestRecursiveDataAndFiniteTypeApplications
type Entry:
    name: String
    nickname: String?

type Person:
    primary: Entry?
