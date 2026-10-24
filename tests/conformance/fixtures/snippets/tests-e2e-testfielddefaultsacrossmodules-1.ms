# conform: tags=diagnostics,generics,lists,records,tier-core
# conform: phase=check
# conform: origin=tests/e2e/e2e_test.go:541 TestFieldDefaultsAcrossModules
def copy[T](value: T) -> T: return value

export type Box[T]:
    value: T
    copied: T = copy(value)
    items: List[T] = [value]
