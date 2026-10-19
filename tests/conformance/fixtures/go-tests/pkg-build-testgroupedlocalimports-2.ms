# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:565 TestGroupedLocalImports
"
fn check() Int:
    return read(value: Value(value: 3))
