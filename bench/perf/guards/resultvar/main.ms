// Guard: a Result variable that is stored to and then tested in a loop owns nothing at
// scope end after the store moved it out; no clone or drop glue runs per pass.
fn make(i Int) Int!:
	if i % 5 == 0: return error(Error("bad"))
	return ok(i)

fn main() Void:
	var total = 0

	for i in 0..300000:
		var r Int! = ok(0)

		if i % 2 == 0: r = make(i)
		else: r = make(i + 1)

		if v := r: total += v

	print(f"{total}")
