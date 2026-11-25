// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/builder_range_test.go:54 TestClosedRangeGrouping
alias := values
// expect-error: MS2001 4:10 unknown binding values; add: import values from "@std/bytes.ms"
// expect-fix: 1:1-1:1 "import values from \"@std/bytes.ms\"\n"
