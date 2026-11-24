// Guard: a scope that closes a resource costs a cleanup registration and nothing else,
// so a close that inlines to nothing adds no cancellation shield.
import Closeable from "@std/core.ms"

type Res {
	id Int
}

fn move Res.close() Void! {
	return ok(void)
}

fn use(i Int) Int! {
	r := Res(i)
	if i < 0 { return error(Error("negative", kind: "EINVAL")) }

	return ok(r.id + 1)
}

fn main() Void! {
	var t = 0
	for i in 0..200000 { t += use(i)? }
	print(t)
}
