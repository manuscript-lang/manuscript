enum Shape:
	Circle(r: Int)
	Square(side: Int)
	Dot

fn side_of(s: Shape) Int:
	n := match s:
		Circle(r):
			return r
		Square(side): side
		Dot: 2

	return n

fn first_leaves(s: Shape) Int:
	n := match s:
		Dot:
			return 0
		Circle(r): r
		Square(side): side

	return n
