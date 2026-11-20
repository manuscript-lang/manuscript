fn label(name: String, hit: Bool) String?:
	if hit: return name + "!"
	return none

fn relabel(name: String) String?:
	return label(name, true)

fn main() Int:
	_kept := relabel("a")
	return 0
