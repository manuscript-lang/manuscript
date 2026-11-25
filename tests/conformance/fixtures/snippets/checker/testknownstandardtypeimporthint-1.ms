// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/inference_hints_test.go:13 TestKnownStandardTypeImportHint
fn boxed(value Partition[Int]) Void => return
// expect-error: MS2001 4:16 unknown type Partition; add: import Partition from "@std/collections/collections.ms"
// expect-fix: 1:1-1:1 "import Partition from \"@std/collections/collections.ms\"\n"
