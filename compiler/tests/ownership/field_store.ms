type Inner:
    x: Int

type Outer:
    inner: Inner
    y: Int

fn bump() Int:
    var o = Outer(Inner(1), 2)
    o.y = 5
    o.inner.x = o.y + 1
    return o.inner.x

fn immutable() Int:
    o := Outer(Inner(1), 2)
    o.y = 5
    return o.y

fn param(var o: Outer) Int:
    o.y = 9
    return o.y

fn compound() Int:
    var o = Outer(Inner(1), 2)
    o.y += 3
    return o.y

fn written_only() Int:
    var o = Outer(Inner(1), 2)
    o.y = 4
    return 0
