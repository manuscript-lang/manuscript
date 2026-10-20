# conform: tags=diagnostics,match,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lint_program_test.go:110 TestMatchArmPayloadBindingsAreLinted
fn answer() Int:
    match parse("1"):
        ok(value): return value
        error(_): return 2
