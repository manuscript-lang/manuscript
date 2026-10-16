export fn add_generic[T: Hashable](items: Set[T], value: T) -> Set[T]:
    return items.add(value)

export fn remove_generic[T: Hashable](items: Set[T], value: T) -> Set[T]:
    return items.remove(value)
