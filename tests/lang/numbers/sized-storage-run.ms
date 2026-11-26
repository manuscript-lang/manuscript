// conform: tags=numbers,types,tier-core
// conform: phase=run
// conform: origin=sized numeric types stage 3
import stdout from "@std/io/io.ms"

type Cell {
	a Int8
	b Int32
	c Float32
	d Bool
	e Int16
}

enum Tok {
	Num(v Int16, s Float32)
	Word(t String, k Int8)
	End
}

fn kind(t Tok) Int {
	match t {
		Num(v, s) => return v.to_int64() + (s.truncate_to_int() or 0)
		Word(text, k) => return text.length() + k.to_int64()
		End => return 0
	}
}

fn main() Void {
	var l List[Int32] = []
	for i in 0..1000 {
		l.append((1000 - i).to_int32() or 0)
	}

	sorted := l.sorted((a, b) => a.compare(b))
	void stdout().write(f"{sorted[0]} {sorted[999]} {l.length()}\n")

	var m = Map[Int16, Int8]()
	for i in 0..300 {
		m.add(i.to_int16() or 0, (i % 100).to_int8() or 0)
	}

	var tot = 0
	for e in m.entries() {
		tot += e.value.to_int64()
	}
	void stdout().write(f"{m.length()} {tot} {m.get(299)}\n")

	var st = Set[Int8]()
	for i in 0..50 {
		st.add((i % 7).to_int8() or 0)
	}
	void stdout().write(f"{st.length()} {st.contains(3)} {st.contains(9)}\n")

	k Int8 := -4
	f Float32 := 1.25
	cl fn(Int) Int := x => ((x.to_int8() or 0) + k).to_int64()
	void stdout().write(f"{cl(10)} {f * 2.0 + 0.5}\n")

	var cells List[Cell] = []
	for i in 0..5 {
		cells.append(Cell(a: -1, b: 100000, c: 0.5, d: true, e: -7))
	}
	void stdout().write(
		f"{cells[4].b} {cells[2].e} {cells[1].c} {cells[0] == cells[3]} {cells[0].d}\n"
	)
	void stdout().write(
		f"{kind(Num(v: 5, s: 2.5))} {kind(Word(t: "ab", k: 3))} {kind(End)}\n"
	)

	opts List[Int8?] := [3, null, -1]
	void stdout().write(f"{opts} {opts[0] == opts[2]}\n")

	ints List[Int8] := [5, 3, -9, 1]
	void stdout().write(
		f"{ints.sorted((a, b) => a.compare(b))} {ints.map(x => x + 1)} {ints.fold(0, (a, x) => a + x.to_int64())}\n"
	)
}
// expect-exit: 0
// expect-stdout: 1 1000 1000
// expect-stdout: 300 14850 some(99)
// expect-stdout: 7 true false
// expect-stdout: 6 3
// expect-stdout: 100000 -7 0.5 true true
// expect-stdout: 7 5 0
// expect-stdout: [some(3), none, some(-1)] false
// expect-stdout: [-9, 1, 3, 5] [6, 4, -8, 2] 0
