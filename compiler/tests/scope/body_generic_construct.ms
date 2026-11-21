type Box[T]:
	value: T

fn wrap[T](value: T) Box[T]:
	return Box(value: value)

fn twice[T](value: T) Box[T]:
	inner := Box(value: value)
	return inner
