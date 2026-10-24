# conform: tags=alternatives,formatter,match,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/constant_before_type_test.go:8 TestConstantMayNameCaseOfLaterType
let initial = Mode.Idle

type Mode:
    case Idle
    case Busy

export def main() -> Int:
    match initial:
        case Idle:
            return 0
        case Busy:
            return 1
