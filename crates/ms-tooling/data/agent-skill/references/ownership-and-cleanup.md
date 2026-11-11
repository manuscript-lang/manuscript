# Ownership and cleanup

Strings, collections and records have one owner; enums follow their payload. Int/Float/Bool and scalar-only enums copy. Binding/field/index reads and non-consuming arguments can borrow. An owner cannot change while borrowed.

Storage in records/collections can move ownership, invalidating the old name. Clone only for an independent owner; copy borrowed fields before storing elsewhere.

<!-- complete: ownership.ms -->
```manuscript
type User:
	name: String

fn name(user: User) String:
	return user.name

fn add(var names: List[String], user: User) Unit:
	names.append(user.name.clone())

fn main() Int:
	user := User("Ada")
	var names = List[String]()
	add(var names, user)
	if name(user) == "Ada" and names.get(0, "") == "Ada": return 0
	return 1
```

Returning part of a parameter borrows it without a marker. Clone for an independent return owner. `:=` is immutable, including contents; var can mutably borrow a collection field.

Mutable parameters require var at declaration and call: `add(var names, user)`. Mutable receiver methods use `fn var Type.name()` but calls remain `value.name()`. Do not mutably capture a collection in its own method's callback.

Closeable closes at scope end unless moved. Declare `fn var Type.close() Unit!` or implement Closeable. Handle explicit close Results; scope-end failures propagate where supported or fault. Cleanup is deterministic, not GC; resource owners are not freely cloneable.
