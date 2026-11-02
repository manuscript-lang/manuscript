# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/field_defaults_test.go:15 TestFieldDefaultBoundaries
type Box[T]:
    value: T = 1
