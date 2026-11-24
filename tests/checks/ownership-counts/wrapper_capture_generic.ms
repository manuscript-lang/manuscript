// expect-debug: allocs=9 alloc_bytes=425
// expect-release: allocs=9 alloc_bytes=425
// Nested wrappers, a generic pass-through and a capture: the baseline that
// owned-argument and return-slot work must not raise.
type Big:
	name String
	items List[Int]

type Wrap:
	inner Big
	tag String

fn mk(n Int) Big:
	var xs = List[Int]()
	for i in 0..n:
		xs.append(i)
	return Big("a name that is long enough to live on the heap", xs)

fn wrap(b Big) Wrap => Wrap(b.clone(), "a tag that is long enough to live on the heap")

fn id(b Big) Big => b

fn pass[T](x T) T => x

fn cap(b Big) fn() Int:
	return () => b.items.length()

export fn main() Int:
	w := wrap(id(mk(8)))
	p := pass(mk(8))
	f := cap(p)
	return f() + w.inner.items.length() - 16
