// conform: tags=closures,diagnostics,strings,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/builder_range_test.go:21 TestClosedBuilderGrouping
read := fn() String => b.build()
// expect-error: MS3070 4:9 a constant takes literals, operators, collections, and other constants; compute this value in a function
