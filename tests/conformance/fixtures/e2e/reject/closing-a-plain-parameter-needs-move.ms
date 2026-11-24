// conform: tags=scope-cleanup,diagnostics,tier-core
// conform: phase=check
// A resource has one owner, so a parameter that the body closes must be declared
// `move`, as a
// `var` method needs a `var` argument.
import Closeable from "@std/core.ms"

type Res:
	id Int
	label String

fn move Res.close() Void!:
	print(f"close {self.id}")

fn consume(res Res) Void!:
	res.close()?
