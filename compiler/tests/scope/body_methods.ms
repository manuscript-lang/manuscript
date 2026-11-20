// Method and interface calls the C body checker claims.
interface Shape:
	fn area() Int
	fn scaled(by: Int) Int

type Square:
	side: Int

fn Square.area() Int: return self.side

fn Square.scaled(by: Int) Int: return self.side * by

fn describe(shape: Shape) Int:
	return shape.area()

fn scale(shape: Shape, k: Int) Int:
	return shape.scaled(k + 1)

fn direct(sq: Square) Int:
	return sq.scaled(2)

type Acc:
	total: Int

fn var Acc.bump(by: Int) Int:
	self.total += by
	return self.total

fn bump_borrowed(acc: Acc) Int:
	return acc.bump(1)

fn make_square(n: Int) Square:
	return Square(side: n)

// A receiver that is a call result is a temporary: borrowed by a method that only reads.
fn chained(n: Int) Int:
	return make_square(n).area() + make_square(n).scaled(2)
