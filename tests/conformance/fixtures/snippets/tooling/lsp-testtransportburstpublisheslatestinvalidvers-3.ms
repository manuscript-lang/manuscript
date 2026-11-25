// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lsp/scheduling_test.go:123 TestTransportBurstPublishesLatestInvalidVersion
fn answer() Int => missing
// expect-error: MS2001 4:20 unknown binding missing; declare it with 'missing := ...' before use, define 'fn missing(...) T { ... }', or import it from a module
