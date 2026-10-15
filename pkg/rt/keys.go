package rt

import "strconv"

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
	Hash    func(K) int64
	Equal   func(K, K) bool
}

// StructuralKeys matches keys by their projection.
func StructuralKeys[K any](project func(K) any) *Keys[K] { return &Keys[K]{Project: project} }

// CustomKeys matches keys by an explicit hash and equality.
func CustomKeys[K any](hash func(K) int64, equal func(K, K) bool) *Keys[K] {
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

var _ = strconv.Itoa
