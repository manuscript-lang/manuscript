package msruntime

import (
	"encoding/binary"
	"math"
	"reflect"
	"strconv"
)

// Keys says how a Map or Set matches keys whose Go equality is not their
// Manuscript equality. A nil *Keys means Go equality: scalars, strings, and
// handles, which match by identity.
//
// Project maps a key to a comparable form such that two keys are equal exactly
// when their projections are; records, alternatives, Optional, Result, Bytes,
// BigInt, and Decimal match structurally this way. A type with an explicit
// Hashable and Equal implementation sets Hash and Equal instead; the lowerer
// binds them to the constructing execution.
type Keys[K any] struct {
	Project func(K) any
	Hash    func(K) int
	Equal   func(K, K) bool
}

// StructuralKeys matches keys by their projection.
func StructuralKeys[K any](project func(K) any) *Keys[K] { return &Keys[K]{Project: project} }

// CustomKeys matches keys by an explicit hash and equality.
func CustomKeys[K any](hash func(K) int, equal func(K, K) bool) *Keys[K] {
	return &Keys[K]{Hash: hash, Equal: equal}
}

// BytesKeys matches Bytes by content.
func BytesKeys() *Keys[*Bytes] { return StructuralKeys(func(b *Bytes) any { return string(b.Data) }) }

// BigIntKeys matches BigInt by value.
func BigIntKeys() *Keys[*BigInt] { return StructuralKeys(func(b *BigInt) any { return b.n.String() }) }

// DecimalKeys matches Decimal by numeric value.
func DecimalKeys() *Keys[*Decimal] {
	return StructuralKeys(func(d *Decimal) any { return d.String() })
}

// KeyBytes is the projection of Bytes inside a structural key.
func KeyBytes(b *Bytes) string { return string(b.Data) }

// KeyBigInt is the projection of BigInt inside a structural key.
func KeyBigInt(b *BigInt) string { return b.n.String() }

// KeyDecimal is the projection of Decimal inside a structural key.
func KeyDecimal(d *Decimal) string { return d.String() }

// HashKey is a deterministic hash of a comparable key projection, so equal
// projections hash alike in every run.
func HashKey(key any) int {
	h := fnvHash(14695981039346656037)
	hashValue(&h, reflect.ValueOf(key))
	return int(h)
}

// fnvHash is FNV-1a; the embedded toolchain carries no hash/fnv.
type fnvHash uint64

func (h *fnvHash) Write(p []byte) {
	for _, b := range p {
		*h = (*h ^ fnvHash(b)) * 1099511628211
	}
}

func hashValue(h *fnvHash, v reflect.Value) {
	if !v.IsValid() {
		h.Write([]byte{0})
		return
	}
	var buf [8]byte
	switch v.Kind() {
	case reflect.Bool:
		if v.Bool() {
			h.Write([]byte{1})
		} else {
			h.Write([]byte{2})
		}
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		binary.LittleEndian.PutUint64(buf[:], uint64(v.Int()))
		h.Write(buf[:])
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64, reflect.Uintptr:
		binary.LittleEndian.PutUint64(buf[:], v.Uint())
		h.Write(buf[:])
	case reflect.Float32, reflect.Float64:
		binary.LittleEndian.PutUint64(buf[:], math.Float64bits(v.Float()))
		h.Write(buf[:])
	case reflect.String:
		binary.LittleEndian.PutUint64(buf[:], uint64(v.Len()))
		h.Write(buf[:])
		h.Write([]byte(v.String()))
	case reflect.Array:
		for i := 0; i < v.Len(); i++ {
			hashValue(h, v.Index(i))
		}
	case reflect.Struct:
		h.Write([]byte(v.Type().String()))
		for i := 0; i < v.NumField(); i++ {
			hashValue(h, v.Field(i))
		}
	case reflect.Interface:
		if v.IsNil() {
			h.Write([]byte{0})
			return
		}
		hashValue(h, v.Elem())
	default:
		// Handles and other reference keys match by identity.
		if v.CanAddr() || v.Kind() == reflect.Pointer || v.Kind() == reflect.Chan || v.Kind() == reflect.Map || v.Kind() == reflect.Func {
			binary.LittleEndian.PutUint64(buf[:], uint64(v.Pointer()))
			h.Write(buf[:])
		}
	}
}

var _ = strconv.Itoa

// ReceiverOf unwraps the view a contract value carries, so a match can ask
// what the value is regardless of which module's implementation wrapped it.
func ReceiverOf(v any) any {
	if r, ok := v.(interface{ Receiver() any }); ok {
		return r.Receiver()
	}
	return v
}
