// conform: tags=testing,tier-core
// conform: phase=check
// A function value owns its captures and has one owner, so a record that holds one is
// not Clonable: neither `.clone()` nor a copying operation such as `concat` applies to
// it.
type Handler:
	name: String
	run: fn(Int) Int

fn pair(handlers: List[Handler]) List[Handler]:
	return handlers.concat(handlers)

export fn main() Int:
	first := Handler(name: "double", run: fn x: x * 2)
	again := first.clone()
	return again.run(2) + pair([first]).length()
