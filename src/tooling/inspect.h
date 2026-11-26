/* tooling/inspect.h: the entities and call sites of a checked program, as `ms map` and `ms map --view review` read them.
 *
 * Ownership: every text lives in the arena the caller gives; the program must outlive the inspection. */
#ifndef MS_TOOLING_INSPECT_H
#define MS_TOOLING_INSPECT_H

#include "base/arena.h"
#include "base/intern.h"
#include "base/message.h"
#include "base/list.h"
#include "compiler/check/program.h"

/* A declaration or method. `id` is `file#kind#name`; a method's is `file#method#offset`. */
typedef struct MsEntity {
  MsSpan id, checker_id, kind, name, ty, file;
  MsPos pos;
  bool exported;
  MsSpanList effects; /* declared effects the callable performs or reaches, sorted */
  MsSpanList permits; /* the `allow_effect` patterns of the callable's own scope, as written */
} MsEntity;

/* A statement, or a constant's initializer, in the module `module`. */
typedef struct MsStatementSite {
  uint32_t module;
  MsPos pos;
} MsStatementSite;

/* A call, construction, operation or cleanup site. */
typedef struct MsCallSite {
  MsSpan id, owner, target, kind, file;
  bool spawn; /* a `TaskGroup.spawn` call */
  MsPos pos;
} MsCallSite;

MS_LIST_DEFINE(MsEntityList, ms_entity_list, MsEntity)
MS_LIST_DEFINE(MsCallSiteList, ms_call_site_list, MsCallSite)
MS_LIST_DEFINE(MsStatementSiteList, ms_statement_site_list, MsStatementSite)

typedef struct MsInspection {
  MsEntityList entities;  /* sorted by id */
  MsCallSiteList calls;   /* sorted by id */
  MsStatementSiteList statements; /* in walk order */
} MsInspection;

/* Collects the project's modules; with `std` the bundled standard library's too. */
void ms_inspect_collect(MsArena *arena, const MsCheckProgram *program, bool std, MsInspection *out);

void ms_inspection_free(MsInspection *inspection);

/* The `ms map --view inspect` document of a checked program, bundled standard modules included: locals, the digest of every
 * source, entities, call sites and statements, as pretty JSON with a closing newline. */
void ms_inspect_document(MsArena *arena, const MsCheckProgram *program, MsStrBuild *out);

/* `file#kind#name` as `file::name`; `+source` is dropped from the file. Any other text is returned as it is. */
MsSpan ms_readable_id(MsArena *arena, MsSpan id);


/* The entity kind and name of a declaration (`fn`, `Shape`; an impl reads `Contract for Receiver`). */
const char *ms_decl_entity_kind(const MsDecl *decl);
MsSpan ms_decl_entity_name(MsArena *arena, const MsCheckProgram *program, const MsDecl *decl);

/* The plain-text call graph and the Mermaid flowchart of an inspection. */
void ms_diagram_ascii(const MsInspection *inspection, MsArena *arena, MsStrBuild *out);
void ms_diagram_mermaid(const MsInspection *inspection, MsArena *arena, MsStrBuild *out);

#endif
