fn step(n: Int) Result[Int, Error]:
	if n < 0:
		return error(Error("negative"))
	return ok(n + 1)

fn main() Result[Void, Error]:
	x := step(1)?
	print(x)
