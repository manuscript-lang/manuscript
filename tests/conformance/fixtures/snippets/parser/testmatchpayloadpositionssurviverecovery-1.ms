# conform: tags=diagnostics,match,tier-core
# conform: phase=check
# conform: origin=pkg/parser/pattern_positions_test.go:13 TestMatchPayloadPositionsSurviveRecovery
# café 🦀
fn use(value: Envelope) Int:
    match value:
        Pair(_, NotFound): return 1
