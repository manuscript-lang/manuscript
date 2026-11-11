// conform: tags=diagnostics
// conform: phase=check
type Key:
    id: Int
impl Equal for Key:
    fn equals(other: Equal) Bool: return true
fn keys() Map[Key, Int]: return Map[Key, Int]()
