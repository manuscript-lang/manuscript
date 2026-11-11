type Counter:
    n: Int

fn var Counter.bump() Int:
    self.n += 1
    return self.n
fn Counter.get() Int: self.n

type Holder:
    c: Counter?

fn bump_param(var c: Counter?) Int?:
    return c?.bump()

fn bump_field(var h: Holder) Int?:
    return h.c?.bump()

fn bump_local() Int?:
    var c: Counter? = Counter(1)
    _first := c?.bump()
    return c?.get()
