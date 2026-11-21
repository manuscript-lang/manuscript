type Config:
	name: String
	retries: Int = 3
	label: String? = none
	title: String = "untitled"

fn retries(c: Config) Int:
	return c.retries

fn name(c: Config) String:
	return c.name

fn make(n: String) Config:
	return Config(name: n)

fn custom(n: String) Config:
	return Config(title: "custom", name: n, retries: 5)

fn main() Int:
	a := make("a")
	b := custom("b")
	return retries(a) + retries(b) + name(a).length + b.title.length
