// conform: tags=diagnostics
// conform: phase=check
type Key:
    value: Int
impl Equal for Key:
    fn equals(other: Equal) Bool: true
impl Hashable for Key:
    fn hash() Int: 0
fn probe() Int:
    values := Map[Key, Int]()
    values.add(Key(1), 10)
    values.add(Key(2), 20)
    return values.length()
