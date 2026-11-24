// removed: Pattern: expr
// use: a one-line match arm is written 'pattern => value'
// fix: v => return v
fn main() Int:
	o Int? := 1
	match o:
		v: return v
		null: return 0
	return 0
