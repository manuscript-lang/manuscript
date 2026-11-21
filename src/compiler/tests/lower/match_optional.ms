fn pick(v: Int?) Int:
	return match v:
		x: x + 1
		none: 0

fn bare(v: Int?) Int:
	return match v:
		x: x * 2
		none: 7

fn name(v: Int?) String:
	return match v:
		_v: "some"
		none: "none"

fn main() Int:
	return pick(3) + bare(none) + name(4).length()
