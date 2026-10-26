# conform: tags=control-flow,formatter,interfaces,maps,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/stdlib_revamp_test.go:15 TestEqualityInterfacesAndHashConsistency
type Key:
    id: Int

impl Equal for Key:
    def equals(other: Key) -> Bool: return True

def keys() -> Map[Key, Int]: return Map[Key, Int]()
