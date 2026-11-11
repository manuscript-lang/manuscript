// conform: tags=testing,tier-core
// conform: phase=check
fn first(items: List[Int]) Int?:
	return items.first()

fn total(items: List[Int]) Int?:
	value := first(items)?
	return value
