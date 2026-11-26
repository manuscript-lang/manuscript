// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/snapshot_test.go:182 TestSnapshotReachableGenerationAndDerivedReuse
export fn value() Int => "wrong"
// expect-error: MS3001 4:26 expected Int, found String (in the return value)
