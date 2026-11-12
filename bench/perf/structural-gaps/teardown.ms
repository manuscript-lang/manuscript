import monotonic from "@std/time.ms"

type Rec:
	id: Int
	name: String
	tags: List[String]

fn build(n: Int) Map[String, Rec]:
	var m = Map[String, Rec]()
	for i in 0..n:
		m["key-number-{i}-padding"] = Rec(
			i,
			"record-name-{i}-padding-text",
			["tag-one-long-enough-{i}", "tag-two-long-enough-{i}"],
		)
	return m

fn main() Unit:
	t0 := monotonic().tick
	m := build(500000)
	t1 := monotonic().tick
	print("built {m.length()} in {(t1 - t0) / 1000000} ms")
