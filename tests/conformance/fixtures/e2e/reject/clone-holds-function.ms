// conform: tags=testing,tier-core
// conform: phase=check
// A function value never changes once made, so it is shared: a record that holds one
// can be copied by `concat` and the copies run the same function.
type Handler:
	name String
	run fn(Int) Int

fn pair(handlers List[Handler]) List[Handler]:
	return handlers.concat(handlers)

export fn main() Int:
	first := Handler(name: "double", run: fn x: x * 2)
	again := first.clone()
	return again.run(2) + pair([first]).length()
