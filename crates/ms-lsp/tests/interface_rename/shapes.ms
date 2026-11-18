interface Shape:
	fn area() Int

type Square:
	side: Int

fn Square.area() Int:
	return self.side * self.side

type Ring:
	width: Int

fn Ring.area(scale: Int) Int:
	return self.width * scale

fn total(shape: Shape) Int:
	return shape.area()

fn main() Void:
	print(total(Square(side: 2)))
	print(Ring(width: 1).area(3))
