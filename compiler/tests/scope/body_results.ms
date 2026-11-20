fn half(n: Int) Int!String:
	if n < 0: return error("negative")
	return ok(n / 2)

fn flag(on: Bool) Bool!Int:
	if on: return ok(true)
	return error(1)

fn main() Void:
	return
