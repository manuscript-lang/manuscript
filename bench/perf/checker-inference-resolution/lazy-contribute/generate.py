"""Concrete argument matching with nested generic patterns and explicit controls."""
import argparse
from pathlib import Path

CONTROLS = {
    'optional-widen-bound': '''fn choose[T](_left: T, _right: T) Int: 0
export fn main() Int:
    plain := 1
    optional: Int? = 1
    return choose(plain, optional)
''',
    'reject-conflict-bound': '''fn choose[T](_left: T, _right: T) Int: 0
export fn main() Int:
    left := 1
    right := "x"
    return choose(left, right)
''',
    'optional-retry': '''fn probe[T](_value: T?) Int: 0
export fn main() Int: probe(1)
''',
    'optional-widen': '''fn choose[T](_left: T, _right: T) Int: 0
export fn main() Int:
    optional: Int? = 1
    return choose(1, optional)
''',
    'optional-plain': '''fn choose[T](_left: T, _right: T) Int: 0
export fn main() Int:
    optional: Int? = 1
    return choose(optional, 1)
''',
    'reject-conflict': '''fn choose[T](_left: T, _right: T) Int: 0
export fn main() Int: choose(1, "x")
''',
    'reject-partial-prefix': '''type Pair[A, B]:
    first: A
    second: B
fn probe[T](_pair: Pair[T, Int], _later: T) Int: 0
export fn main() Int: probe(Pair(1, "x"), "later")
''',
    'reject-callback-type': '''fn probe[T](_value: T, _callback: fn(Int) Int) Int: 0
fn wrong(_x: String) Int: 0
export fn main() Int: probe(1, wrong)
''',
    'reject-callback-arity': '''fn probe[T](_callback: fn(T) Int, _value: T) Int: 0
fn wrong(_x: Int, _y: Int) Int: 0
export fn main() Int: probe(wrong, 1)
''',
    'reject-interface': '''interface Reader[A]:
    fn read() A
type Value:
    value: Int
impl Reader[Int] for Value:
    fn read() Int: self.value
fn probe[T](_value: Reader[T]) Int: 0
export fn main() Int: probe(Value(1))
''',
    'reject-invalid-actual': '''fn probe[T](_value: T) Int: 0
export fn main() Int: probe(missing)
''',
}


def source(depth, calls, explicit):
    nested = 'Chain[' * depth + 'T' + ']' * depth
    s = f'''type Chain[T]:
    value: Int

fn wrap[T: Clonable](_value: T) Chain[T]:
    return Chain[T](0)

fn probe[T: Clonable](_value: {nested}) Int:
    return 0

export fn main() Int:
    v0 := 1
'''
    s += ''.join(f'    v{i} := wrap(v{i-1})\n' for i in range(1, depth + 1))
    call = f'probe{"[Int]" if explicit else ""}(v{depth})'
    s += ''.join(f'    r{i} := {call}\n' for i in range(calls))
    return s + '    return ' + ' + '.join(f'r{i}' for i in range(calls)) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for name, text in CONTROLS.items():
        (args.output / (name + '.ms')).write_text(text)
    for depth in (0, 1, 4, 16, 64, 128):
        for calls in (1, 16, 128):
            for explicit in (False, True):
                name = f'{"explicit" if explicit else "inferred"}-{depth}-{calls}.ms'
                (args.output / name).write_text(source(depth, calls, explicit))
    for explicit in (False, True):
        name = f'{"explicit" if explicit else "inferred"}-4-1000.ms'
        (args.output / name).write_text(source(4, 1000, explicit))
    for width, calls in ((1, 1), (4, 16), (16, 128), (64, 128), (128, 128), (128, 1000), (256, 1000)):
        for explicit in (False, True):
            callback = ', '.join('T' for _ in range(width))
            params = ', '.join(f'_x{i}: Int' for i in range(width))
            s = f'fn probe[T](_callback: fn({callback}) Int) Int: 0\n'
            s += f'fn callback({params}) Int: 0\n\nexport fn main() Int:\n'
            operation = f'probe{"[Int]" if explicit else ""}(callback)'
            s += ''.join(f'    r{i} := {operation}\n' for i in range(calls))
            s += '    return ' + ' + '.join(f'r{i}' for i in range(calls)) + '\n'
            name = f'callable-{"explicit" if explicit else "inferred"}-{width}-{calls}.ms'
            (args.output / name).write_text(s)


if __name__ == '__main__':
    main()
