# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/field_defaults_test.go:14 TestFieldDefaultBoundaries
type Options:
    count: Int = 1
    required: Int

def f() -> Options: return Options()
