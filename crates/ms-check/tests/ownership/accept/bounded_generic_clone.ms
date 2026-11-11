fn copy[T: Clonable](items: List[T]) List[T]:
    return items.clone()

fn main() Int:
    return copy([1, 2]).length() + copy(["a"]).length()
