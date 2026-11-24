// conform: tags=diagnostics,ownership,tier-core
// conform: phase=check
// A function that returns a borrow of its argument is not a function value whose result
// is owned: wrap it in a closure that returns `.clone()` of the call.
fn identity(s String) String:
	return s

fn apply(f fn(String) String, s String) String:
	return f(s)

fn named(s String) String:
	return apply(identity, s)

fn wrapped(s String) String:
	return apply(fn text: identity(text).clone(), s)
