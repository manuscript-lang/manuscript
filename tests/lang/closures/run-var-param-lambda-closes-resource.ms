// conform: tags=closures,tier-core
// conform: phase=run
// A lambda with a `var` parameter whose body closes a resource builds and runs.
import Pipe, ReadStream, pipe from "@std/io/io.ms"

type Handlers {
	items List[fn(var Int, Int) Void!]
}

fn var Handlers.add(f fn(var Int, Int) Void!) Void {
	self.items.append(f)
}

fn make(move p Pipe[Int]) Handlers {
	var h = Handlers(items: List[fn(var Int, Int) Void!]())

	h.add(
		(var total, n) => {
			var out = p.writer()
			out.write(n)?
			out.close()?
			total += n
			return ok()
		}
	)

	return h
}

export fn main() Int {
	var p = pipe[Int](capacity: 4)
	h := make(p)
	var total = 0
	for f in h.items {
		f(total, 5).get_or_else(e => void)
	}
	print(f"{total}")
	return 0
}
// expect-exit: 0
// expect-stdout: 5
