# conform: tags=control-flow,diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/generics.md:32
type Key:
    id: Int

impl Equal for Key:
    fn equals(other: Equal) Bool:
        return true

fn accepts(value: Equal) Unit:
    return

fn use_view() Unit:
    accepts(Equal(Key(1)))
