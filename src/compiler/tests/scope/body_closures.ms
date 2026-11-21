// Function values and closures the C body checker claims.
fn apply(value: Int, transform: fn(Int) Int) Int:
	return transform(value)

fn subtract_one(amount: Int) Int:
	return amount - 1

fn named_value(value: Int) Int:
	return apply(value, subtract_one)

fn captures(value: Int) Int:
	offset := 1
	decrement := fn(item: Int) Int:
		return item - offset
	return apply(value, decrement)

fn inline_lambda(value: Int) Int:
	return apply(value, fn(item: Int) Int: item + 1)

fn context_lambda(value: Int) Int:
	return apply(value, fn item: item * 2)

fn twice(f: fn(Int) Int, value: Int) Int:
	return f(f(value))

fn assigns_capture(value: Int) Int:
	var total = 0

	add := fn(item: Int) Int:
		total += item
		return total

	return add(value)
