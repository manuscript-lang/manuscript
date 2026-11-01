# The runtime keeps the first of equal elements, hashing them when the element type is hashable; the compiler lowers this call from the element type.
export extern fn msrt_list_distinct[T](values: List[T]) List[T]

export extern fn msrt_list_filled[T](
    value: T,
    count: Int,
    max_items: Int?
) List[T]!CollectionError

export extern fn msrt_list_flatten[T](lists: List[List[T]]) List[T]

export extern fn msrt_list_range_by(
    start: Int,
    end: Int,
    step: Int,
    max_items: Int?
) List[Int]!CollectionError
