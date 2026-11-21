// ms: allow_effect std.console.*

fn one() Void:
	print("a")

// ms: allow_effect std.fs.read
fn two() Void:
	print("b")

fn main() Int:
	one()
	two()
	return 0
