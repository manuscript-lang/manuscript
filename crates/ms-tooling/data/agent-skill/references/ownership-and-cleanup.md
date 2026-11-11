# Ownership and cleanup

Strings, collections and records have one owner; enum ownership follows its payload. Int/Float/Bool and scalar-only enums copy. Reads through bindings, fields, indices and non-consuming parameters can borrow rather than copy. An owner cannot change while a live borrow depends on it.

Storing an owned value in a record or collection can move it, invalidating the old name. `.clone()` explicitly makes an independent owner. Copy a borrowed field before storing it elsewhere.

Save as `ownership.ms`:

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

`ms run ownership.ms` prints nothing and exits 0.

- A function returning part of a parameter returns a borrow without a marker. Clone that part when the caller needs an independent owner.
- Mutation parameters use `var` in declaration and call: `fn add(var xs: List[Int]) Unit`, `add(var xs)`. A mutable receiver method instead uses `fn var Type.name()` and ordinary `value.name()` calls.

`:=` is immutable including its contents. A `var` binding to a collection field can mutably borrow that field. Do not capture a collection mutably inside a callback supplied to that same collection's method.

A Closeable closes at scope end unless ownership moved elsewhere. Declare `fn var Type.close() Unit!` or explicitly implement Closeable. Handle an explicit `close()` result; scope-end close failures propagate where supported or fault. Cleanup is deterministic, not garbage collection. Resource-owning values are not freely cloneable.
