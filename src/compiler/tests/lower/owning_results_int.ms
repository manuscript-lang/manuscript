fn parse(n: Int) Result[Int, String]:
	return ok(n)

fn twice(n: Int) Result[Int, String]:
	v := parse(n)?
	return ok(v + v)

fn main() Int:
	return match twice(1):
		ok(v): v
		error(_): 0
