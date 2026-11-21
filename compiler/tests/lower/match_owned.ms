enum Shape:
	Circle(r: Int)
	Square(side: Int)

fn name(s: Shape) String:
	return match s:
		Circle(r): f"circle {r}"
		Square(_): "square"

fn word(n: Int) String:
	return match n:
		0: "zero"
		_: f"n={n}"

fn flag(on: Bool) String:
	return match on:
		true: "on"
		false: "off"

fn bound(n: Int) String:
	label := match n:
		1: "one"
		_: f"other {n}"

	return label

fn main() Int:
	return (
		name(Circle(3)).length()
		+ word(2).length()
		+ flag(true).length()
		+ bound(2).length()
	)
