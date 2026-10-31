# conform: tags=formatter,generics,parser,sets,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/preferred_names/helpers.ms
export fn add_generic[T: Hashable](var items: Set[T], value: T) Unit:
    items.add(value)

export fn remove_generic[T: Hashable](var items: Set[T], value: T) Unit:
    items.remove(value)
