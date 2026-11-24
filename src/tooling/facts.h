/* tooling/facts.h: the review fact model: what the checker established about each callable and type, never text.
 * Port of crates/ms-tooling/src/facts.rs and collect.rs. It is built once from an inspection and the checked program,
 * read by the diagram views and by `ms review`, and lives in the arena it was built in.
 *
 * Ownership: all text and arrays are arena allocated; the program and the inspection need not outlive the model. */
#ifndef MS_TOOLING_FACTS_H
#define MS_TOOLING_FACTS_H

#include "compiler/check/program.h"
#include "tooling/avec.h"
#include "tooling/inspect.h"

/* One line of a view: a label and what hangs under it. Port of tree.rs. `kind` is a flow step kind (call, native,
 * try, scope, spawn, branch, loop, match, arm, exit, closure) or a view node kind. */
typedef struct MsViewNode MsViewNode;
MS_AVEC(MsViewNodes, ms_view_nodes, MsViewNode *)
struct MsViewNode {
  MsSpan label, kind, reference, file;
  size_t line;
  size_t omitted; /* direct nodes omitted by the output cap (on the view root) */
  MsViewNodes kids;
};

typedef enum MsParamMode { MS_MODE_BORROW, MS_MODE_COPY, MS_MODE_MOVE, MS_MODE_UNSPECIFIED } MsParamMode;
typedef enum MsResultOwnership { MS_RESULT_OWNED, MS_RESULT_BORROW } MsResultOwnership;

/* One typed position: a field, a case payload, a parameter, or a result. */
typedef struct MsSlot {
  MsSpan name, ty;
  bool var;      /* a `var` parameter: the callee may change the argument */
  uint8_t mode;  /* MsParamMode, for a parameter without `var` */
  MsSpans refs;  /* keys of the project types the type names */
} MsSlot;
MS_AVEC(MsSlots, ms_slots, MsSlot)

typedef struct MsFact {
  MsSpan key, file, kind, name, label, ty;
  bool exported;
  size_t line;
  MsSpans effects, reach, permits;
  MsSpan error;
  size_t tries, scopes;
  MsSpans calls, external;
  MsSlots slots;
  bool has_result;
  MsSlot result;
  uint8_t result_ownership; /* MsResultOwnership */
  MsSpan receiver;          /* `var`, `move`, `borrow`; empty for anything that is not a method */
  size_t first, last;
  MsViewNodes flow;
  bool has_flow;
} MsFact;
MS_AVEC(MsFactList, ms_fact_list, MsFact)

typedef struct MsImports {
  MsSpan file;
  MsSpans paths;
  MsSpan source;
} MsImports;
MS_AVEC(MsImportList, ms_import_list, MsImports)

typedef struct MsFactModel {
  MsFactList entities; /* sorted by key */
  MsImportList imports; /* sorted by file */
} MsFactModel;

MsFactModel ms_facts_collect(MsArena *arena, MsCheckProgram *program);

/* The fact with `key`, or NULL. */
const MsFact *ms_fact_find(const MsFactModel *model, MsSpan key);

/* A node with a label. */
MsViewNode *ms_view_node(MsArena *arena, MsSpan label);
MsViewNode *ms_view_node_text(MsArena *arena, const char *label);

/* The fact key of the inspection entity with `id` (`keys` holds one per entity, in order), or empty. */
MsSpan ms_entity_key(const MsInspection *inspection, const MsSpan *keys, MsSpan id);

/* The texts of `list` joined by `separator`. */
MsSpan ms_spans_joined(MsArena *arena, const MsSpans *list, const char *separator);

/* The effects of an entity joined by `+`, or `none`. */
MsSpan ms_effects_joined(MsArena *arena, const MsSpans *effects);

#endif
