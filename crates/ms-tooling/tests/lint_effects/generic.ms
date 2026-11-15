interface Sink:
    fn put(s: String) Void

type Out:
    n: Int

fn Out.put(s: String) Void:
    print(s)

fn run[T: Sink](s: T) Void:
    s.put("x")

fn caller() Void:
    run(Out(1))

fn main() Void:
    return
