// conform: tags=control-flow,diagnostics,interfaces,records,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/generics.md:32
type Key:
    id Int

fn Key.equals(other Key) Bool:
    return true

fn accepts(value Equal) Void:
    return

fn use_view() Void:
    accepts(Key(1))
