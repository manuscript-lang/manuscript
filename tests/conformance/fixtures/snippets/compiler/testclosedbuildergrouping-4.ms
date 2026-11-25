// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/builder_range_test.go:23 TestClosedBuilderGrouping
frozen := b.build()
// expect-error: MS3070 4:13 a constant takes literals, operators, collections, and other constants; compute this value in a function
