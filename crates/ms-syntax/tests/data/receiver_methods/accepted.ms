type Held[T]:
	value: T

fn Held[T].get() T:
	return self.value

fn var Held[T].close() Unit!:
	return ok(unit)

fn plain[T](x: T) T:
	return x
