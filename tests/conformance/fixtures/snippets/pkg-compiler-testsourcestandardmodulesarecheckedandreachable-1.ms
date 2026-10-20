# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/source_stdlib_test.go:12 TestSourceStandardModulesAreCheckedAndReachable
.ms"
fn check() Unit:
    let decoded = parse(text: "a: 1")
