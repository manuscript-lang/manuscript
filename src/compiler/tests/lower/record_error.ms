fn explode(n: Int) Int!:
	if n < 0: return error(Error("bad"))
	return ok(n)

fn tagged(n: Int) Int!:
	if n < 0: return error(Error("bad", kind: "EINVAL"))
	return ok(n)

fn empty() Map[String, String]:
	return Map[String, String]()

fn main() Int:
	if explode(1).is_error(): return 1
	if tagged(2).is_error(): return 2

	m := empty()
	return 0
