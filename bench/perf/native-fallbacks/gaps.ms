// Native runtime call against an equivalent written in Manuscript, same input, same
// result. Prints microseconds per case (min of 5).
import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	crc32 from "@std/data/checksum.ms",
	bit_and, bit_not, bit_or, bit_xor, min from "@std/math/math.ms",
	monotonic from "@std/time.ms",
)

fn us(a: Int, b: Int) Int:
	return (b - a) / 1000

fn report(name: String, best: Int, check: Int) Unit:
	print("{name} {best} {check}")

fn data(n: Int) Bytes:
	var b = BytesBuilder()
	var x = 12345

	for i in 0..n:
		x = (x * 1103515245 + 12345) % 2147483648
		b.append((65 + (x / 65536) % 26).to_uint8().get(65))

	return b.build()

// ---- memchr: index_of_byte against a byte loop
fn memchr_ms(b: Bytes, v: UInt8, start: Int) Int:
	n := b.length()
	var i = start

	while i < n:
		if b.get(i, none) == v: return i

		i += 1

	return -1

// ---- the same two scans, eight bytes at a time through int64_le
fn eq_words(a: Bytes, b: Bytes) Bool:
	n := a.length()
	if n != b.length(): return false

	var i = 0

	while i + 8 <= n:
		if a.int64_le(i).get(0) != b.int64_le(i).get(1): return false

		i += 8

	while i < n:
		if a.get(i, none) != b.get(i, none): return false

		i += 1

	return true

fn memchr_words(b: Bytes, v: UInt8, start: Int) Int:
	n := b.length()
	pattern := v.to_int() * 72340172838076673
	var i = start

	while i + 8 <= n:
		w := bit_xor(b.int64_le(i).get(0), pattern)

		// zero byte in w <=> match; classic SWAR test
		if (
			bit_and(
				bit_and(w - 72340172838076673, bit_not(w)),
				-9187201950435737472,
			) != 0
		):
			break

		i += 8

	while i < n:
		if b.get(i, none) == v: return i

		i += 1

	return -1

// ---- blocks of 32 bytes: a fixed trip count with no early exit inside the block
fn eq_blocks(a: Bytes, b: Bytes) Bool:
	n := a.length()
	if n != b.length(): return false

	var i = 0

	while i + 32 <= n:
		var acc = 0
		for j in 0..32:
			acc = bit_or(
				acc,
				bit_xor(
					a.get(i + j, none).to_int(),
					b.get(i + j, none).to_int(),
				),
			)
		if acc != 0: return false

		i += 32

	while i < n:
		if a.get(i, none) != b.get(i, none): return false

		i += 1

	return true

fn memchr_blocks(b: Bytes, v: UInt8, start: Int) Int:
	n := b.length()
	var i = start

	while i + 32 <= n:
		var hit = 0
		for j in 0..32:
			if b.get(i + j, none) == v: hit = 1
		if hit != 0: break

		i += 32

	while i < n:
		if b.get(i, none) == v: return i

		i += 1

	return -1

// ---- equality of two long equal strings against a byte loop
fn eq_ms(a: Bytes, b: Bytes) Bool:
	n := a.length()
	if n != b.length(): return false

	var i = 0

	while i < n:
		if a.get(i, none) != b.get(i, none): return false

		i += 1

	return true

// ---- substring search against a first-byte scan plus compare
fn find_ms(h: Bytes, nd: Bytes) Int:
	hn := h.length()
	nn := nd.length()
	first := nd.get(0, none)
	var i = 0

	while i + nn <= hn:
		if h.get(i, none) == first:
			var j = 1
			while j < nn and h.get(i + j, none) == nd.get(j, none):
				j += 1
			if j == nn: return i

		i += 1

	return -1

// ---- crc32 against a bitwise table loop
fn crc_table() List[Int]:
	var t: List[Int] = []

	for n in 0..256:
		var c = n

		for k in 0..8:
			if c % 2 == 1:
				c = bit_xor(3988292384, c / 2)
			else:
				c /= 2

		t.append(c)

	return t

fn crc_ms(t: List[Int], b: Bytes) Int:
	var c = 4294967295
	n := b.length()
	var i = 0

	while i < n:
		c = bit_xor(t[bit_xor(c, b.get(i, none).to_int()) % 256], c / 256)
		i += 1

	return bit_xor(c, 4294967295)

// ---- stable merge sort of Ints against the runtime sort
fn merge_sort(var a: List[Int], var tmp: List[Int], lo: Int, hi: Int) Unit:
	if hi - lo < 2: return

	if hi - lo <= 12:
		var i = lo + 1

		while i < hi:
			x := a[i]
			var j = i - 1

			while j >= lo and a[j] > x:
				a[j + 1] = a[j]
				j -= 1

			a[j + 1] = x
			i += 1

		return

	mid := (lo + hi) / 2
	merge_sort(var a, var tmp, lo, mid)
	merge_sort(var a, var tmp, mid, hi)

	var i = lo
	var j = mid
	var k = lo

	while i < mid and j < hi:
		if a[j] < a[i]:
			tmp[k] = a[j]
			j += 1
		else:
			tmp[k] = a[i]
			i += 1

		k += 1

	while i < mid:
		tmp[k] = a[i]
		i += 1
		k += 1

	while j < hi:
		tmp[k] = a[j]
		j += 1
		k += 1

	for q in lo..hi:
		a[q] = tmp[q]

// ---- Map[Int, Int] counting against a flat open-addressing table
fn count_ms(keys: List[Int], size: Int) Int:
	var slots: List[Int] = []
	var vals: List[Int] = []

	for i in 0..size:
		slots.append(-1)
		vals.append(0)

	for k in keys:
		var h = ((k * 2654435761) / 65536) % size
		while slots[h] != -1 and slots[h] != k:
			h = (h + 1) % size
		slots[h] = k
		vals[h] += 1

	var total = 0
	for v in vals:
		total += v * v
	return total

fn main() Unit:
	big := data(1000000)
	other := big.clone()
	needle := "ZZZZZZQ".to_bytes()  // absent: full scan
	sa := big.decode_utf8().get("")
	sb := other.decode_utf8().get("")
	var best = 0
	var chk = 0

	// memchr (absent byte)
	best = 1000000000

	for r in 0..5:
		t := monotonic().tick
		chk = big.index_of_byte(48, r).get(-1)
		best = min(best, us(t, monotonic().tick))

	report("memchr-native", best, chk)
	best = 1000000000

	for r in 0..5:
		t := monotonic().tick
		chk = memchr_ms(big, 48, r + bit_and(chk, 1))
		best = min(best, us(t, monotonic().tick))

	report("memchr-ms", best, chk)
	best = 1000000000

	for r in 0..5:
		t := monotonic().tick
		chk = memchr_words(big, 48, r + bit_and(chk, 1))
		best = min(best, us(t, monotonic().tick))

	report("memchr-ms-words", best, chk)
	best = 1000000000

	for r in 0..5:
		t := monotonic().tick
		chk = memchr_blocks(big, 48, r + bit_and(chk, 1))
		best = min(best, us(t, monotonic().tick))

	report("memchr-ms-blocks", best, chk)

	// equality
	best = 1000000000

	for r in 0..5:
		t := monotonic().tick
		chk = 0
		for q in 0..20:
			if sa == sb: chk += 1
		best = min(best, us(t, monotonic().tick))

	report("eq-native-x20", best, chk)
	best = 1000000000

	for r in 0..5:
		t := monotonic().tick
		chk = 0
		for q in 0..20:
			if eq_ms(big, other): chk += 1
		best = min(best, us(t, monotonic().tick))

	report("eq-ms-x20", best, chk)
	best = 1000000000

	for r in 0..5:
		t := monotonic().tick
		chk = 0
		for q in 0..20:
			if eq_words(big, other): chk += 1
		best = min(best, us(t, monotonic().tick))

	report("eq-ms-words-x20", best, chk)
	best = 1000000000

	for r in 0..5:
		t := monotonic().tick
		chk = 0
		for q in 0..20:
			if eq_blocks(big, other): chk += 1
		best = min(best, us(t, monotonic().tick))

	report("eq-ms-blocks-x20", best, chk)

	// substring search
	best = 1000000000

	for r in 0..5:
		t := monotonic().tick
		chk = big.index_of(needle).get(-1)
		best = min(best, us(t, monotonic().tick))

	report("find-native", best, chk)
	best = 1000000000

	for r in 0..5:
		t := monotonic().tick
		chk = find_ms(big, needle)
		best = min(best, us(t, monotonic().tick))

	report("find-ms", best, chk)

	// crc32
	table := crc_table()
	best = 1000000000

	for r in 0..5:
		t := monotonic().tick
		chk = crc32(big).to_int()
		best = min(best, us(t, monotonic().tick))

	report("crc32-native", best, chk)
	best = 1000000000

	for r in 0..5:
		t := monotonic().tick
		chk = crc_ms(table, big)
		best = min(best, us(t, monotonic().tick))

	report("crc32-ms", best, chk)

	// sort
	var xs: List[Int] = []
	var x = 99

	for i in 0..1000000:
		x = (x * 1103515245 + 12345) % 2147483648
		xs.append(x)

	best = 1000000000

	for r in 0..5:
		t := monotonic().tick
		ys := xs.sorted()
		chk = ys[500000]
		best = min(best, us(t, monotonic().tick))

	report("sort-native", best, chk)
	best = 1000000000

	for r in 0..5:
		var ys = xs.clone()
		var tmp = xs.clone()
		t := monotonic().tick
		merge_sort(var ys, var tmp, 0, 1000000)
		chk = ys[500000]
		best = min(best, us(t, monotonic().tick))

	report("sort-ms", best, chk)

	// map counting
	var keys: List[Int] = []

	for i in 0..1000000:
		x = (x * 1103515245 + 12345) % 2147483648
		keys.append(x % 100000)

	best = 1000000000

	for r in 0..5:
		t := monotonic().tick
		var m = Map[Int, Int]()
		for k in keys:
			m[k] = m.get(k).get(0) + 1

		var total = 0
		for v in m.values():
			total += v * v
		chk = total
		best = min(best, us(t, monotonic().tick))

	report("map-native", best, chk)
	best = 1000000000

	for r in 0..5:
		t := monotonic().tick
		chk = count_ms(keys, 262144)
		best = min(best, us(t, monotonic().tick))

	report("map-ms", best, chk)
