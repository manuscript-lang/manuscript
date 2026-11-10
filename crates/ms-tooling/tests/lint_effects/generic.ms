interface Sink:
    fn put(s: String) Unit

type Out:
    n: Int

impl Sink for Out:
    fn put(s: String) Unit:
        print(s)

fn run[T: Sink](s: T) Unit:
    s.put("x")

fn caller() Unit:
    run(Out(1))

fn main() Unit:
    return
