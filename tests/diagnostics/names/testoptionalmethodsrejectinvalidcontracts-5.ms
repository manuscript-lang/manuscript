// conform: tags=diagnostics,formatter,modules,stdlib-optional,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/compiler/optional_test.go:77 TestOptionalMethodsRejectInvalidContracts
import unwrap from "@std/core.ms"
// expect-error: MS2002 4:8-4:14 module does not export unwrap; @std/core.ms exports: Clonable, Closeable, Comparable, Data, Equal, Error, Hashable, Iterator, Optional, Result, Stringable, Writable, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/core.ms"'
