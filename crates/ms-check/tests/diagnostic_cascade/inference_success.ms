type Chain[T]:
    value: Int

fn nested[T](_value: Chain[Chain[T]]) Int: 0
fn optional[T](_value: T?) Int: 0
fn choose[T](left: T, _right: T) T: left
fn callback[T](_value: fn(T) T, _argument: T) Int: 0
fn identity(value: Int) Int: value

fn exercise() Unit:
    chain := Chain[Chain[Int]](0)
    _nested: Int := nested(chain)
    plain := 1
    option: Int? := plain
    _retry: Int := optional(plain)
    _widened: Int? := choose(plain, option)
    _kept: Int? := choose(option, plain)
    _callback: Int := callback(identity, plain)
