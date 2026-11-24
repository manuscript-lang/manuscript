import (
	panic from "@std/core.ms",
	monotonic from "@std/time.ms",
)

type V3:
	x Int
	y Int
	z Int

fn V3.add(o V3) V3:
	return V3(self.x + o.x, self.y + o.y, self.z + o.z)

fn V3.dot(o V3) Int:
	return self.x * o.x + self.y * o.y + self.z * o.z

interface Shape:
	fn area() Int

type Sq:
	s Int

type Rc:
	w Int
	h Int

type Ci:
	r Int

fn Sq.area() Int:
	return self.s * self.s

fn Rc.area() Int:
	return self.w * self.h

fn Ci.area() Int:
	return 3 * self.r * self.r

enum Tok:
	Num(v Int)
	Plus
	Times
	Neg

enum Op:
	Push(v Int)
	Add
	Mul
	Dup
	Pop

type Stack[T]:
	items List[T]

fn var Stack[T].push(v T) Void:
	self.items.append(v)

fn var Stack[T].pop() T?:
	return self.items.pop()

fn lcg(x Int) Int:
	return (x * 1103515245 + 12345) % 2147483648

fn stop(name String, t0 Int, chk Int) Void:
	now := monotonic().tick
	print(f"{name} {(now - t0) / 1000} {chk}")

fn ints(n Int) List[Int]:
	var xs List[Int] = []
	var x = 1

	for i in 0..n:
		x = lcg(x)
		xs.append(x % 1000)

	return xs

fn keep(v Int) Bool:
	return v % 3 != 0

fn scale(v Int) Int:
	return v * 3 + 1

fn c_chain_calls() Int:
	xs := ints(2000000)
	var t = 0
	for r in 0..10:
		t += xs.filter(keep).map(scale).sum()
	return t

fn c_chain_capture() Int:
	xs := ints(2000000)
	var t = 0

	for r in 0..10:
		k := r + 2
		t += xs.filter(fn v: v % k != 0).map(fn v: v * k).sum()

	return t

fn c_zip_dot() Int:
	a := ints(1000000)
	b := ints(1000000)
	var t = 0
	for r in 0..10:
		t += a.zip(b).map(fn p: p.first * p.second).sum()
	return t

fn c_any_all_count() Int:
	xs := ints(2000000)
	var t = 0

	for r in 0..20:
		k := r + 1
		if xs.any(fn v: v == 1000 + k): t += 1
		if xs.all(fn v: v < 2000): t += 2
		t += xs.count(fn v: v % k == 0)

	return t

fn c_fold_record() Int:
	xs := ints(2000000)
	var t = 0

	for r in 0..10:
		a := xs.fold(V3(0, 0, 0), fn acc, v: V3(acc.x + v, acc.y + 1, acc.z + v % 5))
		t += a.x + a.y + a.z

	return t

fn c_take_drop() Int:
	xs := ints(2000000)
	var t = 0
	for r in 0..20:
		t += xs.drop(r).take(1000000).sum()
	return t

fn c_flat_map() Int:
	xs := ints(500000)
	var t = 0
	for r in 0..5:
		t += xs.flat_map(fn v: [v, v + 1, v + 2]).length()
	return t

fn c_chunks_windows() Int:
	xs := ints(500000)
	var t = 0
	for c in xs.chunks(4):
		t += c.sum()
	for w in xs.windows(3):
		t += w[0] + w[2]
	return t

fn c_closure_list() Int:
	var fs List[fn(Int) Int] = []

	for i in 0..16:
		k := i
		fs.append(fn v: v * k + 1)

	var t = 0
	for i in 0..20000000:
		t += fs[i % 16](i)
	return t

fn c_closure_mut() Int:
	var cnt = 0
	var sum = 0
	xs := ints(2000000)

	for r in 0..10:
		xs.for_each(fn v: cnt += 1)
		for v in xs:
			sum += v

	return cnt + sum

fn apply_n(f fn(Int) Int, n Int) Int:
	var t = 0
	for i in 0..n:
		t += f(i)
	return t

fn c_closure_passed() Int:
	k := 7
	return apply_n(fn v: v * k + 1, 50000000)

fn max_of[T Comparable & Clonable](xs List[T]) T:
	var best = xs[0].clone()
	for v in xs:
		if v.compare(best) > 0: best = v.clone()
	return best

fn g_max() Int:
	xs := ints(2000000)
	var t = 0
	for r in 0..20:
		t += max_of(xs)
	return t

fn g_stack() Int:
	var s = Stack[Int](items: [])
	var t = 0

	for r in 0..20:
		for i in 0..500000:
			s.push(i)
		for i in 0..500000:
			t += s.pop() or 0

	return t

fn g_map_user[T, U](xs List[T], f fn(T) U) List[U]:
	var out List[U] = []
	for v in xs:
		out.append(f(v))
	return out

fn g_user_map() Int:
	xs := ints(2000000)
	var t = 0
	for r in 0..10:
		t += g_map_user(xs, fn v: v * 2).length()
	return t

fn i_shapes() Int:
	var xs List[Shape] = []

	for i in 0..1000000:
		if i % 3 == 0: xs.append(Sq(i % 10))
		else if i % 3 == 1: xs.append(Rc(i % 7, i % 5))
		else: xs.append(Ci(i % 4))

	var t = 0
	for r in 0..10:
		for s in xs:
			t += s.area()
	return t

fn e_rpn() Int:
	var prog List[Op] = []

	for i in 0..1000:
		prog.append(Op.Push(i % 10))
		prog.append(Op.Dup)
		prog.append(Op.Mul)
		prog.append(Op.Push(1))
		prog.append(Op.Add)

	var t = 0

	for r in 0..2000:
		var st List[Int] = []

		for op in prog:
			match op:
				Push(v): st.append(v)
				Add:
					b := st.pop() or panic("called Optional.get() on null")
					a := st.pop() or panic("called Optional.get() on null")
					st.append(a + b)
				Mul:
					b := st.pop() or panic("called Optional.get() on null")
					a := st.pop() or panic("called Optional.get() on null")
					st.append(a * b)
				Dup: st.append(st[st.length() - 1])
				Pop: st.pop()

		t += st.length() + st[0]

	return t

fn parse_val(s Int) Int!:
	if s % 1000 == 999: return error(Error("bad"))
	return ok(s * 2)

fn e_result_chain() Int:
	var t = 0

	for i in 0..10000000:
		r := parse_val(i)

		if v := r:
			t += v
		else:
			t -= 1

	return t

fn e_optional_chain() Int:
	var m Map[Int, Int] = {}
	for e in ints(1000).entries():
		m[e.index] = e.value

	var t = 0

	for i in 0..10000000:
		v := m.get(i % 1200)
		if v != null:
			t += v

	return t

fn r_v3_math() Int:
	var acc = V3(0, 0, 0)
	for i in 0..50000000:
		acc = acc.add(V3(i, 1, 2))
	return acc.dot(V3(1, 2, 3))

fn r_sort_field() Int:
	var xs List[V3] = []
	var x = 1

	for i in 0..1000000:
		x = lcg(x)
		xs.append(V3(x % 1000, i, 0))

	ys := xs.sorted_by_key(fn p: p.x)
	return ys[0].y + ys[999999].y

fn r_min_by() Int:
	var xs List[V3] = []
	var x = 1

	for i in 0..1000000:
		x = lcg(x)
		xs.append(V3(x % 1000, i, 0))

	var t = 0
	for r in 0..10:
		t += (
			(
				xs.min_by(fn p: p.x)
				or panic("called Optional.get() on null")
			).y
			+ (
				xs.max_by(fn p: p.x)
				or panic("called Optional.get() on null")
			).y
		)
	return t

fn m_counts() Int:
	xs := ints(2000000)
	c := xs.counts()
	return c.length() + c[7]

fn m_distinct_set() Int:
	xs := ints(2000000)
	d := xs.distinct()
	s := xs.to_set()
	return d.length() + s.length()

fn m_partition() Int:
	xs := ints(2000000)
	p := xs.partition(fn v: v % 2 == 0)
	return p.matching.length() + p.rest.length()

fn m_set_ops() Int:
	a := ints(500000).to_set()
	var b Set[Int] = Set()
	for i in 0..300:
		b.add(i * 3)

	var t = 0
	for r in 0..20:
		t += a.union(b).length() + a.intersection(b).length() + a.difference(b).length()
	return t

fn m_binary_search() Int:
	xs := ints(1000000).sorted()
	var t = 0

	for i in 0..2000000:
		r := xs.binary_search(i % 1000)
		t += r.index

	return t

fn m_group_sum() Int:
	xs := ints(2000000)
	var m Map[Int, Int] = {}
	for v in xs:
		m[v % 500] = m.get_or(v % 500, 0) + v

	var t = 0
	for e in m.entries():
		t += e.value
	return t

fn m_map_of_lists() Int:
	xs := ints(1000000)
	var m Map[Int, List[Int]] = {}

	for v in xs:
		k := v % 1000
		if not m.contains(k): m[k] = []
		m[k].append(v)

	var t = 0
	for e in m.entries():
		t += e.value.length()
	return t

fn run(name String, f fn() Int) Void:
	t0 := monotonic().tick
	c := f()
	stop(name, t0, c)

fn main() Void:
	run("c_chain_calls", c_chain_calls)
	run("c_chain_capture", c_chain_capture)
	run("c_zip_dot", c_zip_dot)
	run("c_any_all_count", c_any_all_count)
	run("c_fold_record", c_fold_record)
	run("c_take_drop", c_take_drop)
	run("c_flat_map", c_flat_map)
	run("c_chunks_windows", c_chunks_windows)
	run("c_closure_list", c_closure_list)
	run("c_closure_mut", c_closure_mut)
	run("c_closure_passed", c_closure_passed)
	run("g_max", g_max)
	run("g_stack", g_stack)
	run("g_user_map", g_user_map)
	run("i_shapes", i_shapes)
	run("e_rpn", e_rpn)
	run("e_result_chain", e_result_chain)
	run("e_optional_chain", e_optional_chain)
	run("r_v3_math", r_v3_math)
	run("r_sort_field", r_sort_field)
	run("r_min_by", r_min_by)
	run("m_counts", m_counts)
	run("m_distinct_set", m_distinct_set)
	run("m_partition", m_partition)
	run("m_set_ops", m_set_ops)
	run("m_binary_search", m_binary_search)
	run("m_group_sum", m_group_sum)
	run("m_map_of_lists", m_map_of_lists)
