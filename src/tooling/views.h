/* tooling/views.h: the diagram views, one question each, built from the fact model, and their renderings: the tree
 * as text, Mermaid and JSON, and the box, signature and flowchart forms of the types, ownership and overview views.
 * Port of crates/ms-tooling/src/{views,tree}.rs. */
#ifndef MS_TOOLING_VIEWS_H
#define MS_TOOLING_VIEWS_H

#include "tooling/facts.h"

/* Bounds one view so a large project stays readable and the output size predictable. */
enum { MS_NODE_CAP = 200 };

/* The fact `name` (a declaration name, `file::name` or a full key) names, or NULL with `error` set. */
const MsFact *ms_find_entity(MsArena *arena, const MsFactModel *model, MsSpan name, MsSpan *error);

/* Builds one question's tree. With `entity` empty the view chooses its roots. False leaves the reason in `error`. */
bool ms_build_view(MsArena *arena, const MsFactModel *model, MsSpan view, MsSpan entity, int64_t depth,
                   MsViewNode **out, MsSpan *error);

/* The tree as an outline with fixed connectors, as a flowchart, and as the `--json` tree object. */
void ms_view_ascii(const MsViewNode *root, MsStrBuild *out);
void ms_view_mermaid(const MsViewNode *root, MsStrBuild *out);
void ms_view_json(const MsViewNode *node, size_t depth, MsStrBuild *out);

/* The view's own rendering, when it has one: false for a view the generic tree renders. */
bool ms_view_ascii_custom(MsArena *arena, const MsFactModel *model, MsSpan view, MsSpan entity, int64_t depth,
                          MsStrBuild *out);
bool ms_view_mermaid_custom(MsArena *arena, const MsFactModel *model, MsSpan view, MsSpan entity, int64_t depth,
                            MsStrBuild *out);

#endif
