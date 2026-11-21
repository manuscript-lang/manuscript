// Operands of two different primitive types, reported where Rust reports them.
fn mixed(x: Int) Int:
	return x + 1.5

fn compare(x: Int, y: Float) Bool:
	return x < y

fn repeat(s: String, n: Int) String:
	return s * n

fn annotated(x: Int, y: Float) Int:
	z: Int := x * y
	return z

fn nested(x: Int, y: Float) Float:
	return (x + y) * 2.0
