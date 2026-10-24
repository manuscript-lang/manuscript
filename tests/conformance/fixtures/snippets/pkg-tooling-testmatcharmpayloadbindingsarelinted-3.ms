# conform: tags=diagnostics,match,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lint_program_test.go:110 TestMatchArmPayloadBindingsAreLinted
def answer() -> Int:
    match parse("1"):
        case ok(value): return value
        case error(_): return 2
