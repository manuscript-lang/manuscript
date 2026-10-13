package msruntime

import (
	"sort"
	"unsafe"
)

// Struct is implemented by the Go struct that generated code declares for a
// nongeneric source record. Statically typed code reads and writes its fields
// directly; the methods serve the runtime's generic operations (formatting,
// equality, hashing, cloning, implementation lookup) and dynamic field access.
type Struct interface {
	StructType() string
	StructNames() []string
	StructGet(index int) Value
	StructSet(index int, value Value)
	StructClone() Struct
}

// ReadField and WriteField access one field of a generated struct. Once the
// program runs concurrent work they take the same sharded lock that guards
// map-backed records, so tasks sharing a record stay memory-safe.
func ReadField[O, T any](owner *O, field *T) T {
	if !concurrentWork.Load() {
		return *field
	}
	lock := ownerLock(unsafe.Pointer(owner))
	lock.RLock()
	defer lock.RUnlock()
	return *field
}

func WriteField[O, T any](owner *O, field *T, value T) {
	if !concurrentWork.Load() {
		*field = value
		return
	}
	lock := ownerLock(unsafe.Pointer(owner))
	lock.Lock()
	defer lock.Unlock()
	*field = value
}

// CopyStruct returns an independent shallow copy of a generated struct.
func CopyStruct[O any](owner *O) *O {
	if concurrentWork.Load() {
		lock := ownerLock(unsafe.Pointer(owner))
		lock.RLock()
		defer lock.RUnlock()
	}
	copied := *owner
	return &copied
}

func structIndex(s Struct, name string) int {
	for i, n := range s.StructNames() {
		if n == name {
			return i
		}
	}
	Panic("runtime invariant: record has no field " + name)
	return -1
}

// structRecord snapshots a generated struct as a map-backed record, which the
// generic read-only operations then treat like any other record.
func structRecord(s Struct) Record {
	names := s.StructNames()
	fields := make(map[string]Value, len(names))
	for i, name := range names {
		fields[name] = s.StructGet(i)
	}
	return Record{s.StructType(), fields}
}

func sortedNames(s Struct) []string {
	names := append([]string(nil), s.StructNames()...)
	sort.Strings(names)
	return names
}

var structFactories = map[string]func() Struct{}

// RegisterStruct lets dynamic construction of a source record build its
// generated struct. Registration happens while the program initializes.
func RegisterStruct(typ string, build func() Struct) { structFactories[typ] = build }
