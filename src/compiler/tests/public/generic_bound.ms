interface Bound:
	fn name() String

export fn pick[T: Bound](x: T) T:
	return x

fn main() Void:
	return
