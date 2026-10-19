# conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
# conform: phase=parse
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
