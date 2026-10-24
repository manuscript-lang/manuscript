# conform: tags=formatter,generics,lists,parser,records,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/e2e_test.go:541 TestFieldDefaultsAcrossModules
def copy[T](value: T) -> T: return value

export type Box[T]:
    value: T
    copied: T = copy(value)
    items: List[T] = [value]
