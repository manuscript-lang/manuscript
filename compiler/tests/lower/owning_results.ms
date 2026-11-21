type Oops:
	code: Int

fn parse(n: Int) Result[String, Oops]:
	if n < 0:
		return error(Oops(n))
	return ok("x")

fn twice(n: Int) Result[String, Oops]:
	v := parse(n)?
	return ok(v)

fn size(n: Int) Int:
	return match twice(n):
		ok(_): 1
		error(_): 0

fn main() Int:
	return size(1)
