// conform: tags=closures,lists,tier-io
// conform: phase=run
// conform: origin=sorted with plain Int comparators uses the integer sort; other comparators stay stable
import stdout from "@std/io/io.ms"

type Item {
	key Int
	tag String
}

fn ascending(left Int, right Int) Int {
	if left < right { return -1 }
	if left > right { return 1 }

	return 0
}

fn descending(left Int, right Int) Int {
	if left > right { return -1 }
	if left < right { return 1 }

	return 0
}

fn shifted(left Int, right Int) Int {
	if left < right + 1 { return -1 }
	return 1
}

fn by_key(left Item, right Item) Int {
	return ascending(left.key, right.key)
}

fn tags(items List[Item]) String {
	var out = ""
	for item in items {
		out = f"{out}{item.key}{item.tag} "
	}
	return out
}

fn main() Void {
	v := [5, 3, 9, 1, 3, 8, -2, 7, 7, 0, 100, -50, 4, 6, 2, 11, 13, 12, 10, 15, 14]
	_a := stdout().write(f"{v.sorted(ascending)}\n")
	_b := stdout().write(f"{v.sorted(descending)}\n")
	_c := stdout().write(f"{v.sorted(shifted)}\n")
	_d := stdout().write(f"{v}\n")
	null List[Int] := []
	_e := stdout().write(f"{null.sorted(ascending)} {[4].sorted(descending)}\n")
	items := [
		Item(key: 2, tag: "a"),
		Item(key: 1, tag: "b"),
		Item(key: 2, tag: "c"),
		Item(key: 1, tag: "d"),
	]
	_f := stdout().write(f"{tags(items.sorted(by_key))}\n")
}
// expect-exit: 0
// expect-stdout: [-50, -2, 0, 1, 2, 3, 3, 4, 5, 6, 7, 7, 8, 9, 10, 11, 12, 13, 14, 15, 100]
// expect-stdout: [100, 15, 14, 13, 12, 11, 10, 9, 8, 7, 7, 6, 5, 4, 3, 3, 2, 1, 0, -2, -50]
// expect-stdout: [-50, -2, 0, 1, 2, 3, 3, 4, 5, 6, 7, 7, 8, 9, 10, 11, 12, 13, 14, 15, 100]
// expect-stdout: [5, 3, 9, 1, 3, 8, -2, 7, 7, 0, 100, -50, 4, 6, 2, 11, 13, 12, 10, 15, 14]
// expect-stdout: [] [4]
// expect-stdout: 1b 1d 2a 2c\x20
