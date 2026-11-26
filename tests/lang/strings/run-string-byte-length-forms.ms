// conform: tags=strings,tier-core
// conform: phase=run
// conform: origin=retire-ms-rt-hot
// Byte length and emptiness of inline, heap, built and empty strings agree on every
// backend.
export fn main() Int {
	a := "héllo"
	b := "plain ascii text that is also longer than fifteen bytes"
	c := a + b
	print(a.length())
	print(b.length())
	print(c.length())
	print("".length())
	print(a.is_empty())
	print("".is_empty())
	print(c.is_empty())
	print(b.view(0, 0).is_empty())
	return 0
}
// expect-exit: 0
// expect-stdout: 6
// expect-stdout: 55
// expect-stdout: 61
// expect-stdout: 0
// expect-stdout: false
// expect-stdout: true
// expect-stdout: false
// expect-stdout: true
