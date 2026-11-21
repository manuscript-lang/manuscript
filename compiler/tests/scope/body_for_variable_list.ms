fn count[T](xs: List[T]) Int:
	var n = 0
	for x in xs:
		n += 1
	return n

fn first_of[T](xs: List[T]) Int:
	for x in xs:
		return 1
	return 0
