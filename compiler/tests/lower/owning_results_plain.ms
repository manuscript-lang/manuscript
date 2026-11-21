type Oops:
	code: Int

fn parse(n: Int) Result[Int, Oops]:
	if n < 0: return error(Oops(n))
	return ok(n)

fn twice(n: Int) Result[Int, Oops]:
	v := parse(n)?
	return ok(v + v)

fn main() Int:
	return match twice(1):
		ok(v): v
		error(_): 0
