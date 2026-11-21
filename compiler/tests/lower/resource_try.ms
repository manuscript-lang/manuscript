type Oops:
	code: Int

type Latch:
	id: Int

fn Latch.close() Void!:
	return ok()

fn open_latch(id: Int) Latch:
	return Latch(id: id)

fn limit(n: Int) Result[Int, Oops]:
	if n > 5: return error(Oops(n))
	return ok(n)

fn run(n: Int) Result[Int, Oops]:
	l := open_latch(n)
	v := limit(l.id)?
	return ok(v + 1)

fn main() Int:
	return match run(3):
		ok(v): v
		error(_): 0
