type Shape:
	width: Int
	height: Int

enum Failure:
	Bad(text: String)

fn area(shape: Shape) Int:
	return shape.width * shape.height

fn read_number(text: String) Int!Failure:
	if value := text.parse_int(): return ok(value)
	return error(Failure.Bad(text))

export fn parse_total(items: List[String]) Int:
	var total = 0
	for item in items:
		total += read_number(item).get_or(0)
	return total + area(Shape(1, 1)) - 1 + perimeter(Shape(0, 0))

fn perimeter(shape: Shape) Int:
	return 2 * (shape.width + shape.height)
