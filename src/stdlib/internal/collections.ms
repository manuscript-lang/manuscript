// The runtime keeps the first of equal elements, hashing them when the element type is
// hashable; the compiler lowers this call from the element type.
export extern fn msrt_list_distinct[T Equal & Clonable](values List[T]) move List[T]

export extern fn msrt_list_range_by(
	start,
	end,
	step Int,
	max_items Int?,
) move List[Int]!
