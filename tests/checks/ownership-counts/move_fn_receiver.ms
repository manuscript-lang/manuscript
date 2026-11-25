// expect-debug: allocs=8
// expect-release: allocs=8
// A `move fn` operation called through an interface takes the payload out of the
// interface value's box: two strings and two boxes, no copy of either name.
type Name {
	text String
}

interface Taken {
	move fn take() Int
}

fn sink(move s Name) Int => s.text.length()

fn move Name.take() Int => sink(self)

fn took(move x Taken) Int => x.take()

fn main() Void {
	print(
		f"{took(Name(f"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb{1}"))}"
	)

	held Taken := Name(f"cccccccccccccccccccccccccccccccccccccccccccccc{2}")
	print(f"{held.take()}")
}
