// conform: tags=strings,tier-core
// conform: phase=run
// `s += piece` writes in place when the block has room: every piece length around the copy
// widths, ASCII and non-ASCII pieces on a string that was ASCII, a piece taken from the
// string itself, and a string that keeps growing past its first block.
fn grow(pieces List[String]) String {
	var s = "start-of-a-string-longer-than-inline"
	for p in pieces { s += p }
	return s
}

fn main() Void {
	var lens = ""
	var s = "0123456789abcdef-header"

	for i in 1..40 {
		s += "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".slice(0, i % 20 + 1)
		lens += f"{s.length()},"
	}

	print(lens)
	print(s)

	var u = "plain ascii prefix that is long enough"
	u += "é"
	u += "x"
	u += "日本"
	print(u.length())
	print(u)

	var v = "another ascii string long enough to be heap"
	v += v.slice(0, 5)
	v += v.slice(3, 9)
	print(v)
	print(
		grow(
			[
				"a", "bb", "ccc", "dddd", "eeeee", "ffffff", "ggggggg", "hhhhhhhh",
				"iiiiiiiii"
			]
		)
	)

	var w = grow(["é", "ab"])
	w += "z"
	print(w.length())
	print(w == grow(["é", "abz"]))

	var m Map[String, Int] = {}
	var k = "key-that-is-long-enough-to-be-heap-"

	for i in 0..5 {
		k += "k"
		m[k.clone()] = i
	}

	print(m.get_or("key-that-is-long-enough-to-be-heap-kkk", -1))
}
// expect-exit: 0
// expect-stdout: 25,28,32,37,43,50,58,67,77,88,100,113,127,142,158,175,193,212,232,233,235,238,242,247,253,260,268,277,287,298,310,323,337,352,368,385,403,422,442,
// expect-stdout: 0123456789abcdef-headerABABCABCDABCDEABCDEFABCDEFGABCDEFGHABCDEFGHIABCDEFGHIJABCDEFGHIJKABCDEFGHIJKLABCDEFGHIJKLMABCDEFGHIJKLMNABCDEFGHIJKLMNOABCDEFGHIJKLMNOPABCDEFGHIJKLMNOPQABCDEFGHIJKLMNOPQRABCDEFGHIJKLMNOPQRSABCDEFGHIJKLMNOPQRSTAABABCABCDABCDEABCDEFABCDEFGABCDEFGHABCDEFGHIABCDEFGHIJABCDEFGHIJKABCDEFGHIJKLABCDEFGHIJKLMABCDEFGHIJKLMNABCDEFGHIJKLMNOABCDEFGHIJKLMNOPABCDEFGHIJKLMNOPQABCDEFGHIJKLMNOPQRABCDEFGHIJKLMNOPQRSABCDEFGHIJKLMNOPQRST
// expect-stdout: 47
// expect-stdout: plain ascii prefix that is long enoughéx日本
// expect-stdout: another ascii string long enough to be heapanothther a
// expect-stdout: start-of-a-string-longer-than-inlineabbcccddddeeeeeffffffggggggghhhhhhhhiiiiiiiii
// expect-stdout: 41
// expect-stdout: true
// expect-stdout: 2
