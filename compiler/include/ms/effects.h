/* Effect directives: the port of crates/ms-check/src/effect_directives.rs. `// ms: effect NAME`
 * declares an effect a function performs, and `// ms: allow_effect PATTERN` permits effects a
 * function (or, in a file's header comment, every function in the file) may reach.
 *
 * Whitespace is ASCII whitespace; the Rust helper also trims Unicode spaces, which a comment
 * holding a directive does not use. */
#ifndef MS_EFFECTS_H
#define MS_EFFECTS_H

#include "ms/base.h"

/* The directive lines found in one comment block. `has_allow` is false when no allow line was
 * written, so an absent scope is distinct from an empty one. */
typedef struct MsDirectives {
    const MsStr *declared;
    const MsStr *allow;
    uint32_t ndeclared;
    uint32_t nallow;
    bool has_allow;
} MsDirectives;

/* The lines of a source file, CR stripped, for header and per-declaration lookups. The text is
 * borrowed, so it must outlive the lines. */
typedef struct MsLines {
    const MsStr *lines;
    uint32_t count;
} MsLines;

MsLines ms_lines_split(MsArena *arena, MsStr source);

/* The file header: `//` lines at the top of the file, ended by a blank line. A comment block that
 * runs straight into code belongs to that declaration, not to the file. */
MsDirectives ms_lines_header(MsArena *arena, MsLines lines);

/* The `//` lines directly above the 1-based `line`, up to a blank or code line, nearest first. */
MsDirectives ms_lines_above(MsArena *arena, MsLines lines, uint32_t line);

/* Whether `effect` matches `pattern`: `*` matches everything, `a.b.*` a prefix, `*.write` a last
 * segment, and any other pattern only itself. */
bool ms_effect_matches(MsStr pattern, MsStr effect);

#endif
