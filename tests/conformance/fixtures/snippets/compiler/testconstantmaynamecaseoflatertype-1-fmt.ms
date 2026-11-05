// conform: tags=alternatives,formatter,match,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/constant_before_type_test.go:8 TestConstantMayNameCaseOfLaterType
let initial = Mode.Idle

enum Mode:
    Idle
    Busy

export fn main() Int:
    match initial:
        Idle:
            return 0
        Busy:
            return 1
