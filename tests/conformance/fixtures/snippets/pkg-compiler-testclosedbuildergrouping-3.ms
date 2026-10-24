# conform: tags=closures,diagnostics,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/builder_range_test.go:22 TestClosedBuilderGrouping
let read = lambda (value: String = b.freeze()) -> String: value
