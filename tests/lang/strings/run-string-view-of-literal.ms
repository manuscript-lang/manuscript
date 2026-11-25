// conform: tags=strings,tier-core
// conform: phase=run
export fn main() Int {
	text := "hello".view(1, 3)
	print(text)
	return 0
}
// expect-exit: 0
// expect-stdout: el
