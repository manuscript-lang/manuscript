// conform: tags=closures,diagnostics,formatter,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/builder_range_test.go:22 TestClosedBuilderGrouping
read := fn(value String = b.build()) String => value
// expect-error: MS3070 4:9 a constant takes literals, operators, collections, and other constants; compute this value in a function
