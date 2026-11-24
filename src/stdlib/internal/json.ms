// Native parse bounds; `parse` and `json_reader` build them from `JsonOptions`.
export type JsonLimits {
	max_bytes, max_depth, max_values Int?
}

// The compiler passes each call the shape table of `T` (src/abi/shape.h) as a hidden
// first argument; the natives are `msstd_json_decode` and `msstd_json_stringify` in
// src/runtime/std/shape_json_*.c.
export extern fn msstd_json_decode[T](
	text String,
	limits JsonLimits,
	ignore_unknown_fields Bool,
) move T!

export extern fn msstd_json_stringify[T](
	value T,
	max_bytes,
	indent Int?,
	strict Bool,
) move String!
