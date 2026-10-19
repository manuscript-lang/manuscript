export fn add_generic[T: Hashable](items: Set[T], value: T) Set[T]:
    items.add(value)
    return items

export fn remove_generic[T: Hashable](items: Set[T], value: T) Set[T]:
    items.remove(value)
    return items
