// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/native_defaults_test.go:54 TestInheritedNativeDefaultsRejectDependenciesAndEffects
fn f(value Bytes = "".to_bytes()) Bytes { ... }
// expect-error: MS2001 4:12 unknown type Bytes; add: import Bytes from "@std/bytes.ms"
// expect-fix: 1:1-1:1 "import Bytes from \"@std/bytes.ms\"\n"
// expect-error: MS2001 4:35 unknown type Bytes; add: import Bytes from "@std/bytes.ms"
// expect-fix: 1:1-1:1 "import Bytes from \"@std/bytes.ms\"\n"
