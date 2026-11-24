// conform: tags=scope-cleanup,diagnostics,tier-core
// conform: phase=check
// A resource cannot leave a holder that stays in use: the holder would close with a
// hole in it. Taking the field and refilling it in the next statement is the way (see
// `ReadStream.end`).
import Closeable from "@std/core.ms"

type Half:
	id Int

fn move Half.close() Void!:
	print(f"close {self.id}")

type Pair:
	first Half
	second Half

fn end_first(var pair Pair) Void!:
	pair.first.close()?
