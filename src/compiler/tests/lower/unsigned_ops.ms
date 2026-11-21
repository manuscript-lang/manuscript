fn unsigned_arith(a: UInt64, b: UInt64) UInt64:
	c := a + b
	d := c * b
	e := d / b
	f := e % b
	return f - a

fn unsigned_order(a: UInt64, b: UInt64) Bool:
	return a < b or a == b or a != b or a >= b

fn sized_divide(a: Int32, b: Int32) Int32:
	return a / b + a % b

fn byte_divide(a: UInt8, b: UInt8) UInt8:
	return a / b
