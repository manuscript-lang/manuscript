/* compiler/own/class.h: value classes, how a value of a type moves.
 *
 * Copy: duplicated implicitly (scalars, alternatives of those, shared-identity handles such as Decimal).
 * Move: one owner; moves at its last use into a moving position and `.clone()` duplicates it explicitly
 * (strings, collections, types holding them, closures, interface values, unbounded type parameters).
 * Resource: a unique `Closeable`; it moves and cannot be copied.
 *
 * Types are interned, so a class is memoized per MsTy in a flat array. A type reached again while its own
 * class is being computed is recursive and is Move; a result that depended on such a cut is not memoized
 * unless it is the outermost one.
 *
 * Ownership: the classifier owns its memo and closeable list; the program is borrowed. */
#ifndef MS_COMPILER_OWN_CLASS_H
#define MS_COMPILER_OWN_CLASS_H

#include "compiler/check/program.h"

typedef enum MsClass { MS_CLASS_COPY, MS_CLASS_MOVE, MS_CLASS_RESOURCE } MsClass;

MS_LIST_DEFINE(MsClassMemo, ms_class_memo, uint8_t)

typedef struct MsClassifier {
  MsCheckProgram *program;
  MsClassMemo memo;    /* owned: by type; 0 unknown, 1 + class, MS_CLASS_ACTIVE while computing */
  MsTyList closeable;  /* owned: concrete types with a `Closeable` implementation of their own */
  uint32_t depth;      /* nesting of class computations in progress */
  uint32_t cuts;       /* recursion cuts so far */
} MsClassifier;

MsClassifier ms_class_new(MsCheckProgram *program);
void ms_class_free(MsClassifier *classifier);

/* Records that `ty` has a `Closeable` implementation of its own (a `close` method satisfying the interface). */
void ms_class_mark_closeable(MsClassifier *classifier, MsTy ty);

MsClass ms_class_of(MsClassifier *classifier, MsTy ty);

/* Whether the value of `expr` is something other than a plain copy: it has a known type that moves or is a resource. */
bool ms_class_owns_memory(const MsFacts *facts, MsClassifier *classifier, const MsExpr *expr);

#endif
