// conform: tags=interfaces,defaults,tier-core
// conform: phase=run
// An omitted argument of an interface operation takes the interface's default, through a bound variable, a view and a method value.
type Opts:
	n: Int = 0

interface Svc:
	fn run(program: String, options: Opts = Opts()) Int

type Cap:
	tag: Int

fn Cap.run(program: String, options: Opts = Opts()) Int:
	return options.n + 1

fn generic_run[T: Svc](service: T) Int:
	return service.run("fake")

fn main() Void:
	print(generic_run(Cap(1)))
	view: Svc := Cap(1)
	print(view.run("x"))
	value := view.run
	print(value("x"))
	print(value("x", Opts(n: 5)))
