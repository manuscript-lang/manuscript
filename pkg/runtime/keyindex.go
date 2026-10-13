package msruntime

import "hash/maphash"

// keyIndex accelerates Map key and Set element lookup. It is derived state: the
// Entries and Items slices stay the source of truth (insertion order, direct
// edits by library code), and the index rebuilds itself when the slice it
// describes was replaced or resized behind its back.
//
// Int and String keys are indexed exactly. Other keys use the Hashable hash
// (a user implementation when present) and are confirmed with equality.
// Collections holding a key that cannot be hashed fall back to a linear scan.
type keyIndex struct {
	ints  map[int64]int
	strs  map[string]int
	other map[uint64][]int
	scan  bool
	n     int // number of keys the index covers; -1 forces a rebuild
	base  any // address of the first key when the index was built
}

type keyed interface {
	count() int
	keyAt(i int) Value
	first() any // address of the first key, nil when empty
	index() *keyIndex
}

var hashSeed = maphash.MakeSeed()

func mixHash(x uint64) uint64 {
	x ^= x >> 33
	x *= 0xff51afd7ed558ccd
	x ^= x >> 33
	x *= 0xc4ceb9fe1a85ec53
	x ^= x >> 33
	return x
}

// keyHash hashes a key consistently with equality. ok is false when the key
// has no usable hash and lookups must scan.
func keyHash(ctx *Execution, v Value) (uint64, bool) {
	switch x := v.(type) {
	case int64:
		return mixHash(uint64(x)), true
	case string:
		return maphash.String(hashSeed, x), true
	case bool:
		if x {
			return 0x9e3779b97f4a7c15, true
		}
		return 0x7f4a7c159e3779b9, true
	case Unit:
		return 0x51ed270b, true
	case Duration:
		return mixHash(uint64(x) ^ 0xd6e8feb86659fd93), true
	case Decimal:
		return maphash.String(hashSeed, x.Value.RatString()), true
	case Bytes:
		return maphash.Bytes(hashSeed, x.Items), true
	case Record, Alternative:
		scope := ctx.EqualityScope
		if method, ok := implementationFunction(v, "@std/Hashable", "hash", scope); ok {
			return mixHash(uint64(Invoke(ctx, method, nil).(int64))), true
		}
		if _, custom := implementationFunction(v, "@std/Equal", "equals", scope); custom {
			return 0, false
		}
		if record, ok := v.(Record); ok {
			h := maphash.String(hashSeed, record.Type)
			for name, field := range record.Fields {
				fh, ok := keyHash(ctx, field)
				if !ok {
					return 0, false
				}
				// Field order is unspecified, so combine commutatively.
				h += mixHash(maphash.String(hashSeed, name) ^ fh)
			}
			return h, true
		}
		alt := v.(Alternative)
		h := maphash.String(hashSeed, alt.Type) ^ mixHash(maphash.String(hashSeed, alt.Tag))
		for _, field := range alt.Fields {
			fh, ok := keyHash(ctx, field)
			if !ok {
				return 0, false
			}
			h = mixHash(h*31 + fh)
		}
		return h, true
	}
	return 0, false
}

func (ix *keyIndex) valid(c keyed) bool {
	n := c.count()
	return ix.n == n && (n == 0 || ix.base == c.first())
}

func (ix *keyIndex) rebuild(ctx *Execution, c keyed) {
	n := c.count()
	*ix = keyIndex{n: n, base: c.first()}
	for i := 0; i < n; i++ {
		if !ix.insert(ctx, c.keyAt(i), i) {
			*ix = keyIndex{scan: true, n: n, base: c.first()}
			return
		}
	}
}

// insert records key at position i, keeping the first position for duplicates.
func (ix *keyIndex) insert(ctx *Execution, key Value, i int) bool {
	switch k := key.(type) {
	case int64:
		if ix.ints == nil {
			ix.ints = map[int64]int{}
		}
		if _, dup := ix.ints[k]; !dup {
			ix.ints[k] = i
		}
	case string:
		if ix.strs == nil {
			ix.strs = map[string]int{}
		}
		if _, dup := ix.strs[k]; !dup {
			ix.strs[k] = i
		}
	default:
		h, ok := keyHash(ctx, key)
		if !ok {
			return false
		}
		if ix.other == nil {
			ix.other = map[uint64][]int{}
		}
		ix.other[h] = append(ix.other[h], i)
	}
	return true
}

func scanKeys(ctx *Execution, c keyed, key Value) int {
	for i, n := 0, c.count(); i < n; i++ {
		if EqualIn(ctx, c.keyAt(i), key) {
			return i
		}
	}
	return -1
}

// lookupKey returns the position of the first key equal to key, or -1.
func lookupKey(ctx *Execution, c keyed, key Value) int {
	if c.count() == 0 {
		return -1
	}
	ix := c.index()
	if !ix.valid(c) {
		ix.rebuild(ctx, c)
	}
	if ix.scan {
		return scanKeys(ctx, c, key)
	}
	switch k := key.(type) {
	case int64:
		if i, ok := ix.ints[k]; ok {
			return i
		}
		return -1
	case string:
		if i, ok := ix.strs[k]; ok {
			return i
		}
		return -1
	}
	h, ok := keyHash(ctx, key)
	if !ok {
		return scanKeys(ctx, c, key)
	}
	for _, i := range ix.other[h] {
		if EqualIn(ctx, c.keyAt(i), key) {
			return i
		}
	}
	return -1
}

// keyAppended updates the index after the key at the end of c was appended.
// The index was synchronized by the lookup that preceded the append.
func keyAppended(ctx *Execution, c keyed) {
	ix := c.index()
	last := c.count() - 1
	if ix.n != last {
		ix.n = -1
		return
	}
	ix.n, ix.base = last+1, c.first()
	if !ix.scan && !ix.insert(ctx, c.keyAt(last), last) {
		*ix = keyIndex{scan: true, n: last + 1, base: c.first()}
	}
}

// keyRemoved updates the index after the key at pos was shifted out of c.
func keyRemoved(ctx *Execution, c keyed, pos int, removed Value) {
	ix := c.index()
	n := c.count()
	if ix.n != n+1 {
		ix.n = -1
		return
	}
	ix.n, ix.base = n, c.first()
	if ix.scan || n == 0 {
		return
	}
	switch k := removed.(type) {
	case int64:
		delete(ix.ints, k)
	case string:
		delete(ix.strs, k)
	default:
		// Positions in hash buckets shift; rebuild on the next lookup.
		ix.n = -1
		return
	}
	for i := pos; i < n; i++ {
		switch k := c.keyAt(i).(type) {
		case int64:
			ix.ints[k] = i
		case string:
			ix.strs[k] = i
		default:
			ix.n = -1
			return
		}
	}
}

func (m *Map) count() int        { return len(m.Entries) }
func (m *Map) keyAt(i int) Value { return m.Entries[i].Key }
func (m *Map) first() any {
	if len(m.Entries) == 0 {
		return nil
	}
	return &m.Entries[0]
}
func (m *Map) index() *keyIndex { return &m.keys }

// find returns the position of key, or -1.
func (m *Map) find(ctx *Execution, key Value) int { return lookupKey(ctx, m, key) }

// put replaces the value of an equal key or appends a new entry.
func (m *Map) put(ctx *Execution, key, value Value) {
	if i := m.find(ctx, key); i >= 0 {
		m.Entries[i].Value = value
		return
	}
	m.Entries = append(m.Entries, Entry{key, value})
	keyAppended(ctx, m)
}

func (m *Map) removeAt(ctx *Execution, pos int) {
	removed := m.Entries[pos].Key
	copy(m.Entries[pos:], m.Entries[pos+1:])
	m.Entries[len(m.Entries)-1] = Entry{}
	m.Entries = m.Entries[:len(m.Entries)-1]
	keyRemoved(ctx, m, pos, removed)
}

func (s *Set) count() int        { return len(s.Items) }
func (s *Set) keyAt(i int) Value { return s.Items[i] }
func (s *Set) first() any {
	if len(s.Items) == 0 {
		return nil
	}
	return &s.Items[0]
}
func (s *Set) index() *keyIndex { return &s.keys }

// find returns the position of value, or -1.
func (s *Set) find(ctx *Execution, value Value) int { return lookupKey(ctx, s, value) }

// add appends value unless an equal element exists.
func (s *Set) add(ctx *Execution, value Value) bool {
	if s.find(ctx, value) >= 0 {
		return false
	}
	s.Items = append(s.Items, value)
	keyAppended(ctx, s)
	return true
}

func (s *Set) removeAt(ctx *Execution, pos int) {
	removed := s.Items[pos]
	copy(s.Items[pos:], s.Items[pos+1:])
	s.Items[len(s.Items)-1] = nil
	s.Items = s.Items[:len(s.Items)-1]
	keyRemoved(ctx, s, pos, removed)
}
