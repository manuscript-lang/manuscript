# conform: tags=control-flow,formatter,interfaces,maps,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_int_map_test.go:61 TestClosedLocalIntMapRejectsCustomKeyEvidence
type Key:
    value: Int

impl Equal for Key:
    fn equals(other: Equal) Bool: true

impl Hashable for Key:
    fn hash() Int: 0

fn probe() Int:
    var values = Map[Key, Int]()
    values.add(Key(1), 10)
    values.add(Key(2), 20)
    return values.length()
