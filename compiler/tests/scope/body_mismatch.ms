// Type mismatches the C body checker reports where Rust reports them.
fn text() Int:
	return "x"

fn widen() Float:
	return 1

fn narrow() Int:
	value: Int := 2.5
	return value

fn flag(n: Int) Bool:
	return n

fn branch(n: Int) Int:
	if n: return 1
	return 2

fn spin(n: Int) Int:
	while n:
		return 1
	return 2

fn shout() String:
	return 3
