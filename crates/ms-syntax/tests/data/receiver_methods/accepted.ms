type Held[T]:
	value: T

fn Held[T].get() T:
	return self.value

fn var Held[T].close() Void!:
	return ok(void)

fn plain[T](x: T) T:
	return x
