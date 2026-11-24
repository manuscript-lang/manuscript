// conform: tags=testing,tier-core
// conform: phase=check
fn push_one(var values List[Int]) Void:
	values.append(1)

export fn main() Int:
	var values List[Int] = []
	// The parameter says `var`; a call never writes it.
	push_one(var values)
	return values.length() - 1
