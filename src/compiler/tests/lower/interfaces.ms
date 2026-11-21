interface Shape:
	fn area() Int
	fn scaled(by: Int) Int

type Square:
	side: Int

fn Square.area() Int:
	return self.side * self.side

fn Square.scaled(by: Int) Int:
	return self.area() * by

fn total(s: Shape) Int:
	return s.area() + s.scaled(2)

fn main() Int:
	return total(Square(side: 3))
