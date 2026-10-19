# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/redundant_labels_test.go:63 TestDropRedundantLabelsSkipsBrokenSource
fn f(a: Int) Int:
    return g(a: a)
