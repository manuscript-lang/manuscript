// removed: if let v = o:
// use: if value := optional:
// fix: if v := o:
fn main() Int:
	o: Int? := 1
	if let v = o:
		return v
	return 0
