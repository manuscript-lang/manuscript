# conform: tags=closures,formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/builder_range_test.go:22 TestClosedBuilderGrouping
let read = fn(value: String = b.freeze()) String: value
