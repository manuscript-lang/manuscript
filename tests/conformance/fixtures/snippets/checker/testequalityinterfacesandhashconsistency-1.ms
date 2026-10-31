# conform: tags=control-flow,diagnostics,interfaces,maps,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/stdlib_revamp_test.go:15 TestEqualityInterfacesAndHashConsistency
type Key:
    id: Int

impl Equal for Key:
    fn equals(other: Key) Bool: return true

fn keys() Map[Key, Int]: return Map[Key, Int]()
