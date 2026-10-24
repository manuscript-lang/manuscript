export def add_generic[T: Hashable](var items: Set[T], value: T) -> Unit:
    items.add(value)

export def remove_generic[T: Hashable](var items: Set[T], value: T) -> Unit:
    items.remove(value)
