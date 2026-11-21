/* abi/layout.h: the memory layouts that generated code and the runtime both rely on. The numbers never
 * change without a change to both sides: the compiler emits code that reads these addresses and tags, and
 * the runtime builds the memory it reads. Each constant that the runtime also states in its own types is
 * checked against them with a _Static_assert. */
#ifndef MS_ABI_LAYOUT_H
#define MS_ABI_LAYOUT_H

#include "base/string.h"

/* ---- task stacks ----
 *
 *   region (256 MiB, aligned to its size)
 *   +--------+--------+-- ... --+--------+---------------------+
 *   | slot 0 | slot 1 |         | slot N | last page: the cell |
 *   +--------+--------+-- ... --+--------+---------------------+
 *   slot = 512 KiB, its lowest 64 KiB a guard that faults when touched; the stack grows down from its end.
 *
 * A region is aligned to its size, so generated code finds the running task's header with one mask of the
 * stack pointer: the last 16 bytes of the region hold the header pointer and the recursion limit. A main
 * task takes a whole region (256 MiB of stack); every other task takes a slot. */
#define MS_STACK_REGION ((size_t)256 << 20)
#define MS_STACK_SLOT ((size_t)512 << 10)
#define MS_STACK_GUARD ((size_t)64 << 10)
#define MS_STACK_PAGE ((size_t)4096)
/* The cell: the header pointer sits this many bytes below the region's end, the recursion limit this many. */
#define MS_STACK_CELL_HDR 16
#define MS_STACK_CELL_LIMIT 8
/* Slots per region: the last page holds the cell, so the top slot is left out. */
#define MS_STACK_SLOTS_PER_REGION ((MS_STACK_REGION - MS_STACK_PAGE) / MS_STACK_SLOT)

_Static_assert(MS_STACK_SLOTS_PER_REGION * MS_STACK_SLOT + MS_STACK_PAGE <= MS_STACK_REGION,
               "the slots and the cell page fit one region");

/* ---- isolates ----
 *
 * Isolate indices fit the promise id's six bits and the token id's twelve. */
#define MS_MAX_ISOLATES 63u
#define MS_NO_ISOLATE UINT32_MAX

/* ---- strings ----
 *
 * A string is two words. The top two bits of the second word are the tag; the rest depends on it (see
 * base/string.h for the full picture). Generated code tests and builds these directly. */
#define MS_STRING_TAG_OWNED 0u  /* first word: the allocation; bits 0..30: the length */
#define MS_STRING_TAG_INLINE 1u /* the bytes are the value (up to 15); length in bits 56..59 */
#define MS_STRING_TAG_STATIC 2u /* first word: bytes that live forever; bits 0..30: the length */
#define MS_STRING_TAG_VIEW 3u   /* first word: borrowed bytes; bits 0..30: the length */
/* Flag in the second word of an owned, static or view string: every byte is ASCII (clear means unknown). */
#define MS_STRING_ASCII_FLAG (UINT64_C(1) << 61)

_Static_assert(MS_STRING_TAG_INLINE == 1u && MS_STRING_TAG_SHIFT == 62, "inline tag sits in the top two bits");
_Static_assert(MS_STRING_INLINE_SHIFT == 56 && MS_STRING_INLINE_MAX == 15, "inline length is in bits 56..59");
_Static_assert(MS_STRING_LENGTH_MASK == (UINT64_C(1) << 31) - 1, "a length takes 31 bits");

#endif
