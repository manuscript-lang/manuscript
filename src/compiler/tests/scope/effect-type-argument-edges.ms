type Sq:
	side: Int

fn Sq.area() Int:
	return self.side * self.side

fn same[T](value: T) T:
	return value

fn run() Int:
	made := same[Sq](Sq(side: 3))
	return made.area()
