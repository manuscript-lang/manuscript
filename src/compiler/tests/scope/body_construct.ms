// Records are built by naming the type; an exported function cannot expose a private
// type.
type Point:
	x: Int
	y: Int

type Hidden:
	value: Int

fn origin() Point:
	return Point(x: 0, y: 0)

fn at(x: Int, y: Int) Point:
	return Point(x, y)

export fn leak() Hidden:
	return Hidden(value: 1)

export fn shown() Point:
	return origin()
