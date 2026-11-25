// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/builder_range_test.go:23 TestClosedBuilderGrouping
frozen := b.build()
// expect-error: MS3070 4:13 a constant takes literals, operators, collections, and other constants; compute this value in a function
