# conform: tags=formatter,match,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lint_program_test.go:106 TestMatchArmPayloadBindingsAreLinted
def answer() -> Int:
    match parse("1"):
        case ok(value): return 1
        case error(e): return 2
