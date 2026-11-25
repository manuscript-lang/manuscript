// conform: tags=testing,tier-core
// conform: phase=check
type Plain {
	value Int
}

export fn main() Int {
	var items = [Plain(2), Plain(1)]
	items.sort()
	return items.length()
}
// expect-error: MS3003 9:11 missing argument compare: fn(Plain, Plain) Int in call to items.sort; add 'compare: <fn(Plain, Plain) Int>'
