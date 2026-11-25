// removed: if c: statement
// use: a ':' no longer opens a block
// fix: none: the closing brace goes after the statement, which is not a one-token edit
fn main() Int {
	if true: return 1
	return 0
}
