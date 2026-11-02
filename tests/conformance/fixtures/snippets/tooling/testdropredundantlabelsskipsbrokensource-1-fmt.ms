# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/redundant_labels_test.go:63 TestDropRedundantLabelsSkipsBrokenSource
fn f(a: Int) Int:
    return g(a: a)
