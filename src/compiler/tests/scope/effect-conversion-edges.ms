interface Shape:
	fn area() Int

type Sq:
	side: Int

fn Sq.area() Int:
	return self.side * self.side

fn total(s: Shape) Int:
	return s.area()

fn run() Int:
	return total(Sq(side: 3))
