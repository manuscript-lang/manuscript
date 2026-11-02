# conform: tags=diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/field_defaults_test.go:15 TestFieldDefaultBoundaries
type Box[T]:
    value: T = 1
