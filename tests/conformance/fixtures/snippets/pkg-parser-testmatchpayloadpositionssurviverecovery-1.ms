# conform: tags=diagnostics,match,tier-core
# conform: phase=check
# conform: origin=pkg/parser/pattern_positions_test.go:13 TestMatchPayloadPositionsSurviveRecovery
# café 🦀
def use(value: Envelope) -> Int:
    match value:
        case Pair(_, NotFound): return 1
