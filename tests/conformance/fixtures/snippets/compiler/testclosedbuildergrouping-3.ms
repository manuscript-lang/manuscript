# conform: tags=closures,diagnostics,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/builder_range_test.go:22 TestClosedBuilderGrouping
let read = fn(value: String = b.build()) String: value
