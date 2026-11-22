[Wiki](../index.md) › [Runtime](index.md)

# Generic natives read and build values through a shape table, not per-type lowering

Decided: `msstd_test_repr[T]`, `msstd_json_stringify[T]` and `msstd_json_decode[T]` get the shape table of `T` (`src/abi/shape.h`) as a hidden first argument and one C walker serves every type. The table is a flat, pointer-free image (shapes, members, strings); what cannot be data (a type's descriptor, `to_string`, JSON forms, field defaults) is in the hook arrays. The runtime never learns a type's layout from anything but its table.

Apply when: adding a type with its own text or JSON form (set `MS_SHAPE_TEXT_FORM` or `MS_SHAPE_JSON_FORM` and the hook), changing a layout the compiler emits, or adding another generic native.
Rules: use a presence byte for an optional whose payload is not a single pointer leaf (a String reads as none when empty and zero-tagged); `NULLABLE` only for records, lists and boxed values. Every shape that owns memory needs `hook.desc`, since a failed decode drops what it built with it. A BOXED record or alternative gives its block size in `value`.
Evidence: [shape.h](../../src/abi/shape.h), [text](../../src/runtime/std/shape_text.c), [JSON write](../../src/runtime/std/shape_json_write.c), [JSON read](../../src/runtime/std/shape_json_read.c), [unit test](../../src/runtime/std/shape_unit.c).
Verify: `ctest --preset debug -R std_shape`; `valgrind --leak-check=full` on `shape_unit` stays clean.
