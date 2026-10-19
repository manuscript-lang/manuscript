export fn add_generic[T: Hashable](var items: Set[T], value: T) Unit:
    items.add(value)

export fn remove_generic[T: Hashable](var items: Set[T], value: T) Unit:
    items.remove(value)
