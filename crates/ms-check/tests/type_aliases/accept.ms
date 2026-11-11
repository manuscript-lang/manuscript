type Row:
	id: Int

type Rows = List[Row]
type Handler = fn(Int) Int
type Maybe[T] = T?
type Pairs[A: Hashable, B] = List[Map[A, B]]
type Later = Defined
type Defined = List[Int]

fn count(rows: Rows) Int:
	return rows.length()

fn load() List[Row]:
	return [Row(id: 1)]

fn run(h: Handler, m: Maybe[Int], p: Pairs[String, Int], l: Later) Int:
	return h(0) + p.length() + l.length()

fn main() Unit:
	n := count(load())
	ys: Rows := load()
	print(n + ys.length())
