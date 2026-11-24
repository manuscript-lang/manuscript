type Shape {
	width Int
	height Int
}

enum Failure {
	Bad(text String)
}

fn area(shape Shape) Int {
	return shape.width * shape.height
}

fn read_number(text String) Int!Failure {
	value := text.parse_int()
	if value != null { return ok(value) }

	return error(Failure.Bad(text.clone()))
}

export fn parse_total(items List[String]) Int {
	var total = 0
	for item in items {
		total += read_number(item).get_or(0)
	}
	return total + area(Shape(1, 1)) - 1
}
