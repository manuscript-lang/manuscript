// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lsp/snapshot_test.go:52 TestSnapshotEquivalentFilenameURIsKeepTheirRequestedText
fn answer() Int => "wrong"
// expect-error: MS3001 4:20 expected Int, found String (in the return value)
