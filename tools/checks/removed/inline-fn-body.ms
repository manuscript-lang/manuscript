// removed: fn f() Int: expr
// use: a one-line function body is written with '=>'
// fix: fn f(a Int) Int => a
fn f(a Int) Int: a
fn main() Int {
	return f(1)
}
