/* Source-level descriptions of a module's types for debug information (debug_types.rs). Both
 * backends turn the same list into their debug format, so what a debugger shows for a `String`, a
 * list, a record, an enum or an optional is decided once, from the machine layout. Entries refer to
 * each other by index and may be cyclic. */
#ifndef MS_MIR_DEBUG_H
#define MS_MIR_DEBUG_H

#include "ms/mir.h"

typedef enum MirDebugKind { MDK_BASE, MDK_STRUCT, MDK_UNION, MDK_POINTER } MirDebugKind;
typedef enum MirDebugEncoding { MDE_BOOL, MDE_SIGNED, MDE_UNSIGNED, MDE_FLOAT } MirDebugEncoding;

typedef struct MirDebugMember {
    MsStr name;
    uint32_t offset; /* bytes from the start of the value */
    uint32_t ty;     /* index into the list */
} MirDebugMember;

typedef struct MirDebugType {
    MsStr name; /* what a debugger shows: `String`, `List[Int]`, `Point` */
    uint32_t size;
    uint8_t kind;     /* MirDebugKind */
    uint8_t encoding; /* MDK_BASE: MirDebugEncoding */
    uint32_t pointee; /* MDK_POINTER: the indexed type, MIR_NONE for unknown data */
    const MirDebugMember *members; /* MDK_STRUCT, MDK_UNION */
    uint32_t nmembers;
} MirDebugType;

typedef struct MirDebugTypes {
    MsArena arena; /* owns every string and array below */
    MirDebugType *types;
    uint32_t ntypes, ctypes;
    uint32_t *of_ty; /* the list index of each MIR type */
    uint32_t nty;
} MirDebugTypes;

/* Describes every type the module declares or uses, once each. `out` is zeroed on entry. */
void mir_debug_types(const MirModule *m, MirDebugTypes *out);
void mir_debug_types_free(MirDebugTypes *t);

/* `path` as debug info should name it: a logical `@std/` path becomes the file under the
 * standard-library sources when they are on disk: under `stdlib_dir` (NULL for none) or the
 * directory the build named. */
MsStr mir_debug_file_name(MsArena *arena, MsStr path, const char *stdlib_dir);
/* Forward slashes and no Windows verbatim prefix. */
MsStr mir_portable_path(MsArena *arena, MsStr path);

#endif
