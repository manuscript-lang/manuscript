// conform: tags=alternatives,match,records,tier-core
// conform: phase=run
// conform: origin=pkg/compiler/constant_before_type_test.go:8 TestConstantMayNameCaseOfLaterType
initial := Mode.Idle

enum Mode:
    Idle
    Busy

export fn main() Int:
    match initial:
        Idle:
            return 0
        Busy:
            return 1
