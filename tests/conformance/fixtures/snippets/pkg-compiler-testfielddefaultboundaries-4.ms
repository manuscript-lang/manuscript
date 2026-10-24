# conform: tags=diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/field_defaults_test.go:14 TestFieldDefaultBoundaries
type Options:
    count: Int = 1
    required: Int

def f() -> Options: return Options()
