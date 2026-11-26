/* tooling/decl_header.h: a function's declaration header as the formatter writes it, so editor text can never spell
 * the language differently from the source the user reads. */
#ifndef MS_TOOLING_DECL_HEADER_H
#define MS_TOOLING_DECL_HEADER_H

#include "tooling/avec.h"

/* The header of the function declared on the line holding `offset` (its name): `fn hold Box.list() &List[Int]`, from any
 * modifiers through the result type, without the body, formatted by `ms_format`. Empty when the line does not declare a
 * function. The text lives in the arena. */
MsSpan ms_declaration_header(MsArena *arena, MsSpan source, size_t offset);

#endif
