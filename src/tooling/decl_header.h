/* tooling/decl_header.h: a function's declaration header as the formatter writes it, so editor text can never spell
 * the language differently from the source the user reads. */
#ifndef MS_TOOLING_DECL_HEADER_H
#define MS_TOOLING_DECL_HEADER_H

#include "tooling/avec.h"

/* The header of the function declared on the line holding `offset` (its name): `fn hold Box.list() &List[Int]`, from any
 * modifiers through the result type, without the body, formatted by `ms_format`. Empty when the line does not declare a
 * function. The text lives in the arena. */
MsSpan ms_declaration_header(MsArena *arena, MsSpan source, size_t offset);

/* Written types to put in place of a declaration's own in `ms_declaration_signature`: the instantiated types of one call. */
typedef struct MsSigTypes {
  const MsSpan *params; /* the type of each parameter, in declaration order; an empty span keeps the written type */
  size_t count;
  MsSpan result; /* the result type (a written `&` stays); empty keeps the written one */
} MsSigTypes;

/* What follows the name of the function `name` declared on the line holding `offset`: its type parameters, parameter list
 * and result, laid out by `ms_format` (`[T](move left T, right T) T`). `types`, when not NULL, replaces the written parameter and result types, so a
 * call shows the types it instantiates. Empty when the line declares no such function. The text lives in the arena. */
MsSpan ms_declaration_signature(MsArena *arena, MsSpan source, size_t offset, MsSpan name, const MsSigTypes *types);

/* The same for a header written as `raw` (`fn Point(x Int, y Int) Point`): a caller whose declaration is not a function, such
 * as a record, writes its constructor's header from the source lines that declare it. */
MsSpan ms_signature_text(MsArena *arena, MsSpan raw, MsSpan name, const MsSigTypes *types);

#endif
