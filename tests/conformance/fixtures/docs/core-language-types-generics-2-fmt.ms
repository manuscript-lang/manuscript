// conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/types/generics.md:32
type Key:
    id: Int

fn Key.equals(other: Key) Bool:
    return true

fn accepts(value: Equal) Unit:
    return

fn use_view() Unit:
    accepts(Key(1))
