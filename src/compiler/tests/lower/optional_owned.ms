fn make(name: String, hit: Bool) String?:
	if hit: return name + "!"
	return none

fn shout(hit: Bool) String:
	if value := make("a", hit): return value + "?"
	return "quiet"

fn size(hit: Bool) Int:
	if value := make("a", hit): return value.length()
	return 0

fn main() Int:
	_s := shout(true)
	return size(false)
