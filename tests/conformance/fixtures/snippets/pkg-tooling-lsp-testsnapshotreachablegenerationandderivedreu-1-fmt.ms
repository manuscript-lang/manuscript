# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/snapshot_test.go:165 TestSnapshotReachableGenerationAndDerivedReuse
from "./dep.ms" import value

export def main() -> Int: value()
