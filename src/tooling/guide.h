/* tooling/guide.h: documentation of the bundled standard library: a snapshot of every importable module read from the
 * embedded sources, and the bounded pages and search `ms search` prints from it.
 * Texts live in the arena. */
#ifndef MS_TOOLING_GUIDE_H
#define MS_TOOLING_GUIDE_H

#include "base/intern.h"
#include "tooling/avec.h"

/* A field, case or operation with its source description. */
typedef struct MsApiMember {
  MsSpan name, kind, signature, doc, contract;
} MsApiMember;
MS_AVEC(MsApiMembers, ms_api_members, MsApiMember)

/* One exported declaration. */
typedef struct MsApiDecl {
  MsSpan name, kind, declaration, doc;
  bool opaque;
  MsSpans effects;
  MsApiMembers members;
} MsApiDecl;
MS_AVEC(MsApiDecls, ms_api_decls, MsApiDecl)

typedef struct MsApiModule {
  MsSpan path; /* `@std/data/json.ms`, or `prelude` */
  MsApiDecls decls;
} MsApiModule;

/* The importable modules, `prelude` first and the rest by path. */
typedef struct MsGuide {
  MsApiModule *modules;
  size_t count;
} MsGuide;

void ms_guide_build(MsArena *arena, MsNames *names, MsGuide *out);

/* `ms search` with no words: every module with a few of its names. */
MsSpan ms_guide_index(MsArena *arena, const MsGuide *guide);

/* The page of a module (`json`), a declaration (`json.parse`) or a member (`prelude.List.sorted`). False leaves the reason. */
bool ms_guide_page(MsArena *arena, const MsGuide *guide, MsSpan path, MsSpan *page, MsSpan *error);

/* One ranked lookup result. */
typedef struct MsGuideMatch {
  MsSpan module, name, kind, signature, doc, path;
  MsSpans effects;
  int64_t score;
} MsGuideMatch;
MS_AVEC(MsGuideMatches, ms_guide_matches, MsGuideMatch)

/* Ranks the standard declarations and members against a loose query. */
MsGuideMatches ms_guide_search(MsArena *arena, const MsGuide *guide, MsSpan query, size_t limit);

#endif
