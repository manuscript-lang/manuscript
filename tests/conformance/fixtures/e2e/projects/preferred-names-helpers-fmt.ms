# conform: tags=formatter,generics,parser,sets,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/preferred_names/helpers.ms
export fn add_generic[T: Hashable](items: Set[T], value: T) Set[T]:
    items.add(value)
    return items

export fn remove_generic[T: Hashable](items: Set[T], value: T) Set[T]:
    items.remove(value)
    return items
