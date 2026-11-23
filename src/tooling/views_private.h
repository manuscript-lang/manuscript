/* Owns views_private.h: the helpers views.c shares with views_custom.c. */
#ifndef MS_TOOLING_VIEWS_PRIVATE_H
#define MS_TOOLING_VIEWS_PRIVATE_H

#include "tooling/views.h"

static inline MsSpan text(const char *literal) {
  return ms_span_of_text(literal);
}

static inline bool is(MsSpan span, const char *literal) {
  return ms_span_is_text(span, literal);
}

static inline bool one_of(MsSpan span, const char *a, const char *b, const char *c) {
  return is(span, a) || (b != NULL && is(span, b)) || (c != NULL && is(span, c));
}

typedef struct Roots {
  const MsFact **ptr;
  size_t len, cap;
} Roots;

void ms_views_roots_push(MsArena *arena, Roots *roots, const MsFact *f);
bool ms_views_is_data_type(const MsFact *f);
const MsFact *ms_views_fact_of(const MsFactModel *model, MsSpan key);
bool ms_views_ownership_candidate(const MsFact *f);
MsSpan ms_views_sanitize(MsArena *arena, MsSpan word, bool alnum_only_underscore);
void ms_views_overview_ascii(MsArena *arena, const MsFactModel *model, MsStrBuild *out);
void ms_views_overview_mermaid(MsArena *arena, const MsFactModel *model, MsStrBuild *out);

#endif
