import ignore, scaled, tagged from "./lib.ms"

fn local(value: Float, step: Float = 0.5) Float:
	return value + step

fn main() Int:
	a := scaled(2)
	b := scaled(2, 5)
	text := tagged("hi")
	ignore(text)
	ignore(a, true)
	c := local(1.0)
	if c > 1.0:
		return a + b + text.length()
	return 0
