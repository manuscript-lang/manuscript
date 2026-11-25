// conform: tags=ownership,control-flow
// conform: phase=run
// `r` moves into `get_or` only inside the `if`, so a join holds it flagged. Returning from inside the loop
// after that move must still release it through its flag, and the unmoved path releases
// it at the end.
fn make(n Int) Map[String, String]! {
	var m = Map[String, String]()
	m["PATH"] = "x"
	if n == 0 { return error(Error("none")) }

	return ok(m)
}

fn found(n Int, key String) Bool {
	r := make(n)
	if r.is_ok() {
		for entry in r.get_or(Map[String, String]()).entries() {
			if entry.key == key { return true }
		}
	}
	return false
}

fn main() Void {
	print(found(1, "PATH"))
	print(found(1, "HOME"))
	print(found(0, "PATH"))
}
// expect-exit: 0
// expect-stdout: true
// expect-stdout: false
// expect-stdout: false
