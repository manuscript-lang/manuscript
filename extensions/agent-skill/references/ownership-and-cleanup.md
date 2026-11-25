# Ownership and cleanup

Strings, collections and records have one owner; enums follow their payload. Int/Float/Bool and scalar-only enums copy. **Borrow by default, `move` is the only slot that owns, `.clone()` is the only copy.** Nothing copies behind your back, and a borrow can never outlive or change its owner.

- **Reading borrows.** A plain parameter, `x := y`, a loop variable, a match payload and `xs[i]` read in place. The owner stays yours but cannot change while a borrow is in use.
- **Changing is declared.** `var p T` in a signature lets the body change the argument; `var y = x.part` borrows exclusively, so changes reach `x`. Call sites write neither: `add(names, user)`.
- **Keeping is declared.** Storing a value (a field, a collection, a return that is not a part of an argument) takes it, so the parameter says `move p T`. The caller's name is dead after the call; the argument moves at its last use, or pass `.clone()` to keep the original.
- **Results that are part of an argument say so.** `fn hold User.name() &String` returns a borrow of the receiver; `hold` marks the argument the result keeps using, `&` marks the result (no space after `&`). A result without `&` is a new value. A body that returns a part of any argument without `hold` and `&` is an error: write them, or return `.clone()`. `Optional` and `Result` carry borrowed payloads the same way: `fn hold Box.find(key String) &Item?`.
- **An owned value may go where a borrow is expected, never the reverse.** A borrow (a loop variable, an element, a `split` piece) cannot go into a `move` parameter or an owned slot: `.clone()` it.
- **Function-typed parameters take no `move`, `hold` or `&`.** The compiler decides from what the callee does with the function.

<!-- complete: ownership.ms -->
```manuscript
type User {
    name String
}

fn hold User.label() &String {
    return self.name
}

fn add(var names List[String], user User) Void {
    names.append(user.name.clone())
}

fn adopt(var users List[User], move user User) Void {
    users.append(user)
}

fn main() Int {
    user := User("Ada")
    var names = List[String]()
    add(names, user)

    var users = List[User]()
    adopt(users, user)

    if users[0].label() == "Ada" and names.get_or(0, "") == "Ada" { return 0 }

    return 1
}
```

`:=` is immutable, including contents; `var` can mutably borrow a collection field. Mutable receiver methods use `fn var Type.name()` but calls remain `value.name()`. Do not mutably capture a collection in its own method's callback. A `&` record field (`items &List[String]`) stores a pointer to a value another binding owns; the record is tied to that owner, cannot outlive it and cannot be stored in an owned place (see "Looks" below).

Closeable closes at scope end unless moved. Declare `fn move Type.close() Void!` or implement Closeable. `x.close()` moves `x` like any `move` method: a later use or second close is a use after move, and scope end skips it. Only an owner closes: take a parameter with `move` to close it. Handle explicit close Results; scope-end failures propagate where supported or fault. Cleanup is deterministic, not GC; resource owners are not freely cloneable.

## Borrow errors and their fixes

A loop variable, a parameter and an element read are borrowed, so storing one needs `.clone()`; reading one needs nothing. The error "is a view of another value, not an owner, and cannot be moved here" means write `x.clone()`, declare the parameter `move`, or use `x` only where it is read.

<!-- complete: ownership-borrows.ms -->
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

Pieces of a value are borrows too: `line.split(" ")`, `xs.first()`, `m.keys()`, `xs.slice(a, b)` and `xs[i]` borrow their source, so store them with `.clone()`: `out.append(line.split(" ").clone())`. Fields move the same way: `out.append(user.name.clone())`, never `out.append(user.name)`. A store `m[key] = v` takes `key` after `v` ran, so `v` may read it: `counts[key] = counts.get_or(key, 0) + 1`. Do not use `key` after the store unless it is a scalar; store `key.clone()` to keep it. A list parameter changes only if declared `var xs List[Int]`; otherwise copy it into a `var` local first (`var ys = xs.clone()`).

`Map.get_or`, `List.first`, `find`, `min` and `max` return borrows, so a mutable copy of one is `var x = m.get_or(k, []).clone()`. Hand the changed value back with `m.add(k, x)`.

## Looks: records that keep looking at a value

A record with a `&` field is a *look*: it stores a pointer to a value that something else owns, copies nothing and frees nothing. Building it ties it to its sources, which freeze until the look's last use; it cannot be returned unless a `hold` argument supplies the source, stored in an owned place, sent over a pipe or cloned. A look with `fn var next() &T?` iterates in `for` and hands out borrowed items with no clones. There is no stdlib cursor type: write the small record where you need it.

<!-- complete: look.ms -->
```manuscript
type Walk {
    items &List[String]
    at Int
}

fn var Walk.next() &String? {
    if self.at >= self.items.length() { return null }

    self.at += 1
    return self.items[self.at - 1]
}

fn walk(hold names List[String]) Walk {
    return Walk(names, 0)
}

fn main() Void {
    names := ["a", "b", "c"]
    for n in walk(names) {
        print(n)
    }
}
```

## Trees and linked lists change through `fn var` methods

A recursive type holds its child as `Node?`. An `Optional` payload cannot be mutably borrowed with `if var n = self.left { ... }`, and a field cannot move out of its owner (`m.left = insert(m.left, k)` fails). Change a child in place with a `fn var` method and call it through the field with `?.`: the call does nothing when the child is absent. Walk with a plain function that borrows and narrows the Optional (`if node != null { ... }`).

A `T?` parameter defaults to `null`, so it must come after the required parameters: write `find(key Int, node Node?)`, not `find(node Node?, key Int)`.

<!-- complete: bst-insert.ms -->
```manuscript
type Node {
    key Int
    left, right Node?
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
    if node != null {
        keys(out, node.left)
        out.append(node.key)
        keys(out, node.right)
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
