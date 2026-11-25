// conform: tags=testing,tier-core
// conform: phase=check
type Plain {
	value Int
}

export fn main() Int {
	return [Plain(2), Plain(1)].sorted().length()
}
// expect-error: MS3003 8:33 missing argument compare: fn(Plain, Plain) Int in call to sorted; add 'compare: <fn(Plain, Plain) Int>'
