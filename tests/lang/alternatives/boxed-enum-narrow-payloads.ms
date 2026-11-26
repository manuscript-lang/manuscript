// conform: tags=alternatives,match,tier-core,testing
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Pt {
	ok Bool
	tiny Int8
	wide UInt16
}

// A self-containing enum keeps its payload in a heap block whose slots are as wide as
// their values, so a read must sign- or zero-extend exactly its own slot and a release
// build must accept narrow integers and Float32.
enum Chain {
	End
	Link(next Chain, small Int8, mid Int32, flag UInt8, half Float32)
	At(next Chain, point Pt)
}

fn total(c Chain) Int {
	match c {
		End => {
			return 0
		}
		Link(next, small, mid, flag, half) => {
			return (
				small.to_int()
				+ mid.to_int()
				+ flag.to_int()
				+ (half.truncate_to_int() or 0)
				+ total(next)
			)
		}
		At(next, point) => {
			return point.tiny.to_int() + point.wide.to_int() + total(next)
		}
	}
}

test "narrow payloads of a self-containing enum read back with their sign" {
	chain := Chain.Link(
		Chain.At(Chain.End, Pt(ok: true, tiny: -3, wide: 65535)),
		-5,
		-70000,
		255,
		2.5,
	)
	expect_equal(total(chain), -5 - 70000 + 255 + 2 - 3 + 65535)?
	expect_equal(total(chain.clone()), total(chain))?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
