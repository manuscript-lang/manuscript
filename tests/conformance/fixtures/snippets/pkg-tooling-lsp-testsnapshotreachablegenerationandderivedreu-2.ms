# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/snapshot_test.go:166 TestSnapshotReachableGenerationAndDerivedReuse
export def value() -> Int:
    let unused = 1
    return 2
