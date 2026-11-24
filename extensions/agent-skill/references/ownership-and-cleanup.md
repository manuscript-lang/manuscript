# Ownership and cleanup

Strings, collections and records have one owner; enums follow their payload. Int/Float/Bool and scalar-only enums copy. Binding/field/index reads and non-consuming arguments can borrow. An owner cannot change while borrowed.

Storage in records/collections can move ownership, invalidating the old name. Clone only for an independent owner; copy borrowed fields before storing elsewhere.

<!-- complete: ownership.ms -->
```manuscript
type User {
    name String
}

fn name(user User) String {
    return user.name
}

fn add(var names List[String], user User) Void {
    names.append(user.name.clone())
}

fn main() Int {
    user := User("Ada")
    var names = List[String]()
    add(names, user)
    if name(user) == "Ada" and names.get_or(0, "") == "Ada" { return 0 }

    return 1
}
```

Returning part of a parameter borrows it without a marker. Clone for an independent return owner. `:=` is immutable, including contents; var can mutably borrow a collection field.

Mutable parameters require var at declaration and call: `add(var names, user)`. Mutable receiver methods use `fn var Type.name()` but calls remain `value.name()`. Do not mutably capture a collection in its own method's callback.

Closeable closes at scope end unless moved. Declare `fn move Type.close() Void!` or implement Closeable. `x.close()` moves `x` like any `move` method: a later use or second close is a use after move, and scope end skips it. Only an owner closes: take a parameter with `move` to close it. Handle explicit close Results; scope-end failures propagate where supported or fault. Cleanup is deterministic, not GC; resource owners are not freely cloneable.

## Borrow errors and their fixes

A loop variable, a parameter and an element read are borrowed, so storing one needs `.clone()`; reading one needs nothing. The error `cannot move x out: it is borrowed` means write `x.clone()`, or use `x` only where it is read.

```manuscript
fn copy_all(items List[String]) List[String] {
    var out = List[String]()
    for s in items {
        out.append(s.clone())
    }
    return out
}

fn has(items List[String], want String) Bool {
    for s in items {
        if s == want { return true }
    }
    return false
}
```

Pieces of a value are borrows too: `line.split(" ")`, `s.slice(a, b)` and `xs[i]` borrow their source, so store them with `.clone()`: `out.append(line.split(" ").clone())`. A store `m[key] = v` takes `key` after `v` ran, so `v` may read it: `counts[key] = counts.get_or(key, 0) + 1`. Do not use `key` after the store; store `key.clone()` to keep it.

Fields move the same way: `out.append(user.name.clone())`, never `out.append(user.name)`. A list parameter changes only if declared `var xs List[Int]` and called `add(xs)`; otherwise copy it into a `var` local first.

## Trees and linked lists change through `fn var` methods

A recursive type holds its child as `Node?`. An `Optional` payload cannot be mutably borrowed with `if var n = slot { ... }` or `var n = slot.get()`, and a field cannot move out of its owner (`m.left = insert(m.left, k)` fails). Change a child in place with a `fn var` method and call it through the field with `?.`: the call does nothing when the child is absent. Walk with a plain function that borrows (`if n := node { ... }`).

A `T?` parameter defaults to `null`, so it must come after the required parameters: write `find(key Int, node Node?)`, not `find(node Node?, key Int)`.

<!-- complete: bst-insert.ms -->
```manuscript
type Node {
    key Int
    left Node?
    right Node?
}

fn var Node.insert(key Int) Void {
    if key < self.key {
        if self.left == null {
            self.left = Node(key, null, null)
        } else {
            self.left?.insert(key)
        }
    } else {
        if self.right == null {
            self.right = Node(key, null, null)
        } else {
            self.right?.insert(key)
        }
    }
}

fn keys(var out List[Int], node Node?) Void {
    if n := node {
        keys(out, n.left)
        out.append(n.key)
        keys(out, n.right)
    }
}

fn main() Int {
    var root = Node(50, null, null)
    for k in [30, 70, 20, 40] {
        root.insert(k)
    }

    var out = List[Int]()
    keys(out, root)
    if out == [20, 30, 40, 50, 70] { return 0 }

    return 1
}
```

An empty tree is a `Node?` that is `null` (or an enum with an `Empty` case); give the owner a type with a `var root Node?` and make its `insert` method create the first node.
