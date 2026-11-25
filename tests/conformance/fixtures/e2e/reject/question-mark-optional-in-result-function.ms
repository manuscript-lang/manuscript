// conform: tags=testing,tier-core
// conform: phase=check
fn first(items List[Int]) Int? {
	return items.first()
}

fn total(items List[Int]) Int! {
	value := first(items)?
	return ok(value)
}
// expect-error: MS3000 8:14 '?' on an Optional leaves the function when the value is absent, so the function must return an Optional or Void; declare it to return T?, or use 'if x != null', or 'x or default'
