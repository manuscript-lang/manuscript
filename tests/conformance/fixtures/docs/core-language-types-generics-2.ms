# conform: tags=control-flow,diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/generics.md:32
type Key:
    id: Int

impl Equal for Key:
    def equals(other: Key) -> Bool:
        return True

def accepts(value: Equal) -> Unit:
    return

def use_view() -> Unit:
    accepts(Key(1))
