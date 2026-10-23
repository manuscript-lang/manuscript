# conform: tags=control-flow,formatter,interfaces,maps,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/stdlib_revamp_test.go:15 TestEqualityInterfacesAndHashConsistency
type Key:
    id: Int

impl Equal for Key:
    fn equals(other: Equal) Bool: return true

fn keys() Map[Key, Int]: return Map[Key, Int]()
