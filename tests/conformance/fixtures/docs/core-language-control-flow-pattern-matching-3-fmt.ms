# conform: tags=alternatives,formatter,match,parser,records,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/control-flow/pattern-matching.md:59
type Position:
    case Point(x: Int, y: Int)
    case Unknown

fn horizontal(position: Position) Int:
    match position:
        Position.Point(horizontal_value, _):
            return horizontal_value
        Position.Unknown:
            return 0
