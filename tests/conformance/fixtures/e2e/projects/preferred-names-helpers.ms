# conform: tags=diagnostics,generics,sets,tier-core
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/preferred_names/helpers.ms
export def add_generic[T: Hashable](var items: Set[T], value: T) -> Unit:
    items.add(value)

export def remove_generic[T: Hashable](var items: Set[T], value: T) -> Unit:
    items.remove(value)
