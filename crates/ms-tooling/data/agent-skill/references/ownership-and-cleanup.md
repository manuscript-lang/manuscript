# Ownership and cleanup

Strings, collections, records and payload enums have one owner. Int/Float/Bool and payload-free enums copy. Reads and non-consuming arguments borrow; an owner cannot change while borrowed. Storing moves the value and kills the old name.

<!-- complete: ownership.ms -->
```manuscript
type User:
	name: String

fn name(user: User) String:
	return user.name

fn add(var names: List[String], user: User) Void:
	names.append(user.name.clone())

fn main() Int:
	user := User("Ada")
	var names = List[String]()
	add(var names, user)
	if name(user) == "Ada" and names.get_or(0, "") == "Ada": return 0
	return 1
```

- Returning part of a parameter borrows it, no marker. Clone for an independent owner. `:=` is deeply immutable.
- Mutable parameters need `var` at declaration and call: `add(var names, user)`. `fn var Type.name()` is called plainly.
- **Borrowed values need `.clone()` to store**: a loop variable, a parameter, a field, an element, `line.split(" ")`, `s.slice(a, b)`. `cannot move x out: it is borrowed` means `x.clone()`. A store `m[k] = v` takes `k` after `v` runs, so `counts[k] = counts.get_or(k, 0) + 1` works; do not use `k` afterwards unless cloned.
- A list parameter changes only as `var xs: List[Int]` called `add(var xs)`; otherwise copy to a `var` local.
- An escaping closure or promise takes what it captures: clone first to keep your copy.

## Closing
A `fn move T.close() Void!` (or `Closeable` from `@std/core.ms`) closes at scope end on every exit, last declared first; holders (records, lists, maps, optionals) close their parts, and replacing or removing a part closes the old one. `x.close()` **consumes** `x`: a later use or second close is a use after move and scope end skips it. Call it only to handle its error (`file.close()?`). A scope-end close error becomes the function's error, or faults when there is nowhere to return it. Only an owner closes: take a `move` parameter. Resources are not `Clonable`. A factory returns an open resource by moving it. `xs.pop()` hands an element out.

## Trees and linked lists
A recursive type holds children as `Node?`. Change a child with a `fn var` method called through the field with `?.` (a no-op when absent); `m.left = insert(m.left, k)` and `if var n = slot:` fail. Walk with a borrowing function. A `T?` parameter defaults to `none`, so it comes after required ones.

<!-- complete: bst-insert.ms -->
```manuscript
type Node:
	key: Int
	left: Node?
	right: Node?

fn var Node.insert(key: Int) Void:
	if key < self.key:
		if self.left.is_none():
			self.left = Node(key, none, none)
		else:
			self.left?.insert(key)
	else:
		if self.right.is_none():
			self.right = Node(key, none, none)
		else:
			self.right?.insert(key)

fn keys(var out: List[Int], node: Node?) Void:
	if n := node:
		keys(var out, n.left)
		out.append(n.key)
		keys(var out, n.right)

fn main() Int:
	var root = Node(50, none, none)
	for k in [30, 70, 20, 40]:
		root.insert(k)

	var out = List[Int]()
	keys(var out, root)
	if out == [20, 30, 40, 50, 70]: return 0

	return 1
```
