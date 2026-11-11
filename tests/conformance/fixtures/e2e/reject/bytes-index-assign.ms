// conform: tags=testing,tier-core
// conform: phase=check
export fn main() Int:
	var data = "abc".to_bytes()
	data[0] = 1
	return 0
