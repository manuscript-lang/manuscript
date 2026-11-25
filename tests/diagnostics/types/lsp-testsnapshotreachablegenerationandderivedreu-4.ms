// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/snapshot_test.go:197 TestSnapshotReachableGenerationAndDerivedReuse
export fn value() Int => "private error"
// expect-error: MS3001 4:26 expected Int, found String (in the return value)
