// conform: tags=testing,tier-core
// conform: phase=check
export fn main() Int:
	scores := {"a": 1}
	scores["b"] = 2
	return scores["a"]
