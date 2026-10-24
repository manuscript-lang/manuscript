# conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/generics.md:32
type Key:
    id: Int

impl Equal for Key:
    def equals(other: Equal) -> Bool:
        return True

def accepts(value: Equal) -> Unit:
    return

def use_view() -> Unit:
    accepts(Key(1))
