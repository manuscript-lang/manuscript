package msruntime

import (
	"hash/maphash"
	"sort"
)

// keyIndex accelerates Map key and Set element lookup. It is derived state: the
// Entries and Items slices stay the source of truth (insertion order, direct
// edits by library code), and the index rebuilds itself when the slice it
// describes was replaced or resized behind its back.
//
// Int and String keys are indexed exactly. Other keys use the Hashable hash
// (a user implementation when present) and are confirmed with equality. The
// checker rejects key types that are not Hashable, so an unhashable key at run
// time is an invariant violation.
type keyIndex struct {
	ints  map[int64]int
	strs  map[string]int
	other map[uint64][]int
	n     int // number of keys the index covers; -1 forces a rebuild
	base  any // address of the first key when the index was built
	// The maps store a stable id per key rather than its position, so removing
	// an entry does not renumber the keys after it. ids lists the live ids in
	// position order (ascending), so a position is found by binary search. It
	// is nil while ids equal positions, which holds until a key is removed from
	// anywhere but the end.
	ids  []int
	next int // the id the next appended key receives
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

// keyHash hashes a key consistently with equality.
func keyHash(ctx *Execution, v Value) uint64 {
	switch x := v.(type) {
	case int64:
		return mixHash(uint64(x))
	case string:
		return maphash.String(hashSeed, x)
	case bool:
		if x {
			return 0x9e3779b97f4a7c15
		}
		return 0x7f4a7c159e3779b9
	case Unit:
		return 0x51ed270b
	case Duration:
		return mixHash(uint64(x) ^ 0xd6e8feb86659fd93)
	case Instant:
		// Equality also checks the clock domain, which faults on a mismatch.
		return mixHash(uint64(x.Tick) ^ 0x2545f4914f6cdd1d)
	case libraryBigInt:
		return maphash.String(hashSeed, x.n.String())
	case libraryTimestamp:
		return mixHash(uint64(x.t.UnixNano()))
	case Decimal:
		return maphash.String(hashSeed, x.Value.RatString())
	case Bytes:
		return maphash.Bytes(hashSeed, x.Items)
	case View:
		child := *ctx
		child.EqualityScope = x.Scope
		return keyHash(&child, x.Receiver)
	case Struct, Record, Alternative:
		scope := ctx.EqualityScope
		if method, ok := implementationFunction(v, "@std/Hashable", "hash", scope); ok {
			return mixHash(uint64(Invoke(ctx, method, nil).(int64)))
		}
		if _, custom := implementationFunction(v, "@std/Equal", "equals", scope); custom {
			Panic("runtime invariant: key type overrides Equal without Hashable")
		}
		if s, ok := v.(Struct); ok {
			v = structRecord(s)
		}
		if record, ok := v.(Record); ok {
			h := maphash.String(hashSeed, record.Type)
			for name, field := range record.Fields {
				// Field order is unspecified, so combine commutatively.
				h += mixHash(maphash.String(hashSeed, name) ^ keyHash(ctx, field))
			}
			return h
		}
		alt := v.(Alternative)
		h := maphash.String(hashSeed, alt.Type) ^ mixHash(maphash.String(hashSeed, alt.Tag))
		for _, field := range alt.Fields {
			h = mixHash(h*31 + keyHash(ctx, field))
		}
		return h
	}
	Panic("runtime invariant: map key or set element is not Hashable")
	return 0
}

func (ix *keyIndex) valid(c keyed) bool {
	n := c.count()
	return ix.n == n && (n == 0 || ix.base == c.first())
}

func (ix *keyIndex) rebuild(ctx *Execution, c keyed) {
	n := c.count()
	*ix = keyIndex{n: n, base: c.first(), next: n}
	for i := 0; i < n; i++ {
		ix.insert(ctx, c.keyAt(i), i)
	}
}

// insert records key under id, keeping the first id for duplicates.
func (ix *keyIndex) insert(ctx *Execution, key Value, id int) {
	switch k := key.(type) {
	case int64:
		if ix.ints == nil {
			ix.ints = map[int64]int{}
		}
		if _, dup := ix.ints[k]; !dup {
			ix.ints[k] = id
		}
	case string:
		if ix.strs == nil {
			ix.strs = map[string]int{}
		}
		if _, dup := ix.strs[k]; !dup {
			ix.strs[k] = id
		}
	default:
		h := keyHash(ctx, key)
		if ix.other == nil {
			ix.other = map[uint64][]int{}
		}
		ix.other[h] = append(ix.other[h], id)
	}
}

// pos converts a live id to its current position.
func (ix *keyIndex) pos(id int) int {
	if ix.ids == nil {
		return id
	}
	return sort.SearchInts(ix.ids, id)
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
	switch k := key.(type) {
	case int64:
		if id, ok := ix.ints[k]; ok {
			return ix.pos(id)
		}
		return -1
	case string:
		if id, ok := ix.strs[k]; ok {
			return ix.pos(id)
		}
		return -1
	}
	for _, id := range ix.other[keyHash(ctx, key)] {
		if i := ix.pos(id); EqualIn(ctx, c.keyAt(i), key) {
			return i
		}
	}
	return -1
}

// lookupInt is lookupKey for an Int key.
func lookupInt(ctx *Execution, c keyed, key int64) int {
	if c.count() == 0 {
		return -1
	}
	ix := c.index()
	if !ix.valid(c) {
		ix.rebuild(ctx, c)
	}
	if id, ok := ix.ints[key]; ok {
		return ix.pos(id)
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
	id := ix.next
	ix.next++
	if ix.ids != nil {
		ix.ids = append(ix.ids, id)
	}
	ix.insert(ctx, c.keyAt(last), id)
}

// keyRemoved updates the index after the key at pos was shifted out of c.
func keyRemoved(ctx *Execution, c keyed, pos int, removed Value) {
	ix := c.index()
	n := c.count()
	if ix.n != n+1 {
		ix.n = -1
		return
	}
	if n == 0 {
		// Nothing remains, so no id in the old maps is valid.
		*ix = keyIndex{}
		return
	}
	var id int
	switch {
	case ix.ids != nil:
		id = ix.ids[pos]
		ix.ids = append(ix.ids[:pos], ix.ids[pos+1:]...)
	case pos == n:
		// The last key left and ids still equal positions.
		id = pos
		ix.next = n
	default:
		ix.ids = make([]int, n+1)
		for i := range ix.ids {
			ix.ids[i] = i
		}
		id = pos
		ix.ids = append(ix.ids[:pos], ix.ids[pos+1:]...)
	}
	ix.n, ix.base = n, c.first()
	switch k := removed.(type) {
	case int64:
		delete(ix.ints, k)
	case string:
		delete(ix.strs, k)
	default:
		if !ix.unlinkHashed(ctx, removed, id) {
			ix.n = -1
		}
	}
}

// unlinkHashed drops id of the removed hashed key from its bucket. It reports
// false when the bucket does not hold id (for example an unstable user hash),
// so the caller can fall back to a full rebuild.
func (ix *keyIndex) unlinkHashed(ctx *Execution, removed Value, id int) bool {
	h := keyHash(ctx, removed)
	bucket := ix.other[h]
	at := -1
	for j, b := range bucket {
		if b == id {
			at = j
			break
		}
	}
	if at < 0 {
		return false
	}
	if len(bucket) == 1 {
		delete(ix.other, h)
	} else {
		ix.other[h] = append(bucket[:at], bucket[at+1:]...)
	}
	return true
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
		m.ownEntries()
		m.Entries[i].Value = value
		return
	}
	m.Entries = append(m.Entries, Entry{key, value})
	keyAppended(ctx, m)
}

// ownEntries gives the map a private backing array before an in-place write.
func (m *Map) ownEntries() {
	if m.shared {
		m.Entries = append([]Entry(nil), m.Entries...)
		m.shared = false
	}
}

func (s *Set) ownItems() {
	if s.shared {
		s.Items = append([]Value(nil), s.Items...)
		s.shared = false
	}
}

func (m *Map) removeAt(ctx *Execution, pos int) {
	m.ownEntries()
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
	s.ownItems()
	removed := s.Items[pos]
	copy(s.Items[pos:], s.Items[pos+1:])
	s.Items[len(s.Items)-1] = nil
	s.Items = s.Items[:len(s.Items)-1]
	keyRemoved(ctx, s, pos, removed)
}
