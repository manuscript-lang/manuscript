type Bag[T]:
    items: Set[T]

fn make[T](x: T) Set[T]: Set[T]()
