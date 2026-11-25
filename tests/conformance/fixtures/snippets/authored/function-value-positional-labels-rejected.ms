// conform: tags=diagnostics,functions,tier-core
// conform: phase=check
// conform: origin=issue 3211
fn identity(value Int) Int => value

fn join(first String, second String) String => first + second

fn _hidden(_value Int) Int => _value

fn numbered(_0 Int, _1 Int) Int => _0 + _1

export fn main() Int {
	transform fn(Int) Int := identity
	combine fn(String, String) String := join
	keep fn(Int) Int := _hidden
	text := combine(first: "a", second: "b")
	other := combine("a")
	direct := _hidden(other: 1)
	named := numbered(value: 2)
	short := numbered(_0: 1)
	copy := identity
	copied := copy(value: 3)
	kept := identity(value: 3)
	return transform(value: 2) + keep(1)
}
// expect-error: MS3004 16:21 unknown argument first; function values take positional arguments (String, String), so pass them without labels
// expect-error: MS3004 16:33 unknown argument second; function values take positional arguments (String, String), so pass them without labels
// expect-error: MS3003 16:13 missing argument 1: String in call to combine; pass it positionally, without a label
// expect-error: MS3003 16:13 missing argument 2: String in call to combine; pass it positionally, without a label
// expect-error: MS3003 17:14 missing argument 2: String in call to combine; pass it positionally, without a label
// expect-error: MS3004 18:23 unknown argument other; parameters of _hidden: _value
// expect-error: MS3003 18:15 missing argument _value: Int in call to _hidden; add '_value: <Int>'
// expect-error: MS3004 19:23 unknown argument value; parameters of numbered: _0, _1
// expect-error: MS3003 19:14 missing argument _0: Int in call to numbered; add '_0: <Int>'
// expect-error: MS3003 19:14 missing argument _1: Int in call to numbered; add '_1: <Int>'
// expect-error: MS3003 20:14 missing argument _1: Int in call to numbered; add '_1: <Int>'
// expect-error: MS3004 22:20 unknown argument value; function values take positional arguments (Int), so pass them without labels
// expect-error: MS3004 24:22 unknown argument value; function values take positional arguments (Int), so pass them without labels
// expect-error: MS3003 24:12 missing argument 1: Int in call to transform; pass it positionally, without a label
