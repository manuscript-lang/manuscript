fn twice[T: Clonable](value: T) List[T]:
    return [value.clone(), value]

fn run() Int:
    return twice(fn() Int: 1).length()

export fn main() Int:
    return 0
