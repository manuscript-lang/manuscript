fn nop(n: Int) Void:
	return

fn side(x: Int) Int:
	p := fn(y: Int) Void:
		return
	p(x)
	nop(x)
	return x

export fn main() Int:
	return side(3)
