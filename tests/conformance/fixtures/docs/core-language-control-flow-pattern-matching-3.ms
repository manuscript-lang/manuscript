# conform: tags=alternatives,diagnostics,match,records,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/control-flow/pattern-matching.md:59
type Position:
    case Point(x: Int, y: Int)
    case Unknown

def horizontal(position: Position) -> Int:
    match position:
        case Position.Point(horizontal_value, _):
            return horizontal_value
        case Position.Unknown:
            return 0
