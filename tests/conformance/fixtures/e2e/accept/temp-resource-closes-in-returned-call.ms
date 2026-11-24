// conform: tags=cleanup,resources,closures
// conform: phase=run
// A resource built as an argument of a returned call closes before the function leaves, in a function and in a closure.
type Out:
	n Int

fn move Out.close() Void!:
	print("close out")
	return ok()

fn make() Out:
	return Out(n: 1)

fn read(o Out) Int!:
	return ok(o.n)

fn through() Int!:
	return read(make())

fn main() Void!:
	f := fn() Int! => return read(make())
	void through()
	print("after through")
	void f()
	print("after closure")
