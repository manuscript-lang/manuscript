// conform: tags=syntax,tier-core
// conform: phase=run

// A lambda groups names that share a type as a function does; `ms fmt` writes this
// form.
fn main() Void {
	add := fn(a, b Int) Int { return a + b }
	scaled := fn(x, y Int, factor Float) Float { return (x + y).to_float() * factor }
	print(f"{add(1, 2)} {scaled(1, 2, 1.5)}")
}
