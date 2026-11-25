// conform: tags=scope-cleanup,diagnostics,tier-core
// conform: phase=check
// A resource has one owner, so a parameter that the body closes must be declared
// `move`, as a
// `var` method needs a `var` argument.
import Closeable from "@std/core.ms"

type Res {
	id Int
	label String
}

fn move Res.close() Void! {
	print(f"close {self.id}")
}

fn consume(res Res) Void! {
	res.close()?
}
// expect-error: MS3000 17:12 the body keeps `res`, so the signature must say so: write `move res Type`, or keep `.clone()` of it
// expect-error: MS3000 18:5 cannot pass `res` as a `move` receiver: it is not declared `move`, so the caller keeps it; write `move res <Type>` in the signature
