package msruntime

import (
	"maps"
	"reflect"
	"sync"
	"sync/atomic"
	"unsafe"
)

// Clone copies a data value's own storage. Nested values retain their references.
func Clone(value Value) Value {
	switch v := value.(type) {
	case Struct:
		return v.StructClone()
	case Record:
		return Record{v.Type, fieldsCopy(v.Fields)}
	case Alternative:
		return Alternative{v.Type, v.Tag, append([]Value{}, v.Fields...)}
	case *libraryHeaders:
		return v.clone()
	case *List:
		return &List{Type: v.Type, Items: append([]Value{}, v.Items...)}
	case *Map:
		return &Map{Type: v.Type, Entries: append([]Entry{}, v.Entries...)}
	case *Set:
		return &Set{Type: v.Type, Items: append([]Value{}, v.Items...)}
	case Bytes:
		return Bytes{append([]byte{}, v.Items...)}
	default:
		return Panic("clone requires a record, alternative, or collection")
	}
}

// Record fields live in Go maps, and an unsynchronized concurrent write is an
// unrecoverable process crash. Once the program starts concurrent work, field
// access goes through a lock chosen by the field map's identity, so tasks that
// share a record see ordinary (if racy at the program level) reads and writes.
var concurrentWork atomic.Bool

const fieldLockShards = 64

var fieldLocks [fieldLockShards]sync.RWMutex

// markConcurrent records that more than one goroutine may run source code.
func markConcurrent() { concurrentWork.Store(true) }

func fieldLock(fields map[string]Value) *sync.RWMutex {
	return &fieldLocks[(reflect.ValueOf(fields).Pointer()>>4)%fieldLockShards]
}

func ownerLock(owner unsafe.Pointer) *sync.RWMutex {
	return &fieldLocks[(uintptr(owner)>>4)%fieldLockShards]
}

func readField(fields map[string]Value, name string) Value {
	if !concurrentWork.Load() {
		return fields[name]
	}
	lock := fieldLock(fields)
	lock.RLock()
	defer lock.RUnlock()
	return fields[name]
}

func writeField(fields map[string]Value, name string, value Value) {
	if !concurrentWork.Load() {
		fields[name] = value
		return
	}
	lock := fieldLock(fields)
	lock.Lock()
	defer lock.Unlock()
	fields[name] = value
}

// fieldsSnapshot returns fields safe to iterate while other tasks write. The
// copy is taken under the lock so callers may recurse without holding it.
func fieldsSnapshot(fields map[string]Value) map[string]Value {
	if !concurrentWork.Load() {
		return fields
	}
	lock := fieldLock(fields)
	lock.RLock()
	defer lock.RUnlock()
	return maps.Clone(fields)
}

// fieldsCopy returns an independent copy of a record's fields.
func fieldsCopy(fields map[string]Value) map[string]Value {
	if !concurrentWork.Load() {
		return maps.Clone(fields)
	}
	return fieldsSnapshot(fields)
}
