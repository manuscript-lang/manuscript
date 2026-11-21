interface Src[T]:
	var fn next() T?!
	move fn close() Void!

type Pipe[T]:
	id: Int

fn var Pipe[T].next() T?!:
	return ok(none)

fn move Pipe[T].close() Void!:
	return ok()

fn take(s: Src[Int]) Int:
	return 1

fn go(p: Pipe[Int]) Int:
	return take(p)
