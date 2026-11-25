/* tooling/review.h: classifies what changed between a base and a head program and ranks it. */
#ifndef MS_TOOLING_REVIEW_H
#define MS_TOOLING_REVIEW_H

#include "tooling/facts.h"

typedef struct MsFinding {
  MsSpan id, tier, entity, location;
  MsSpans changes;
  size_t reach;
  int64_t score;
  MsSpans terms, evidence;
} MsFinding;
MS_AVEC(MsFindings, ms_findings, MsFinding)

typedef struct MsTouched {
  MsSpan file;
  const int64_t *lines;
  size_t count;
} MsTouched;
MS_AVEC(MsTouchedList, ms_touched_list, MsTouched)

/* The changed-file information a diff review needs. */
typedef struct MsDiffInput {
  size_t files, sources;
  MsSpans added;        /* project-relative files that did not exist before */
  MsTouchedList touched; /* a file's changed head lines */
  size_t insertions, deletions;
  bool base_checked;
} MsDiffInput;

extern const char *const MS_TIER_CONTRACT, *const MS_TIER_EFFECT, *const MS_TIER_ERROR, *const MS_TIER_RESOURCE,
    *const MS_TIER_INTERNAL;

/* Classifies what changed between base and head, ranked: score, then tier, then id. */
MsFindings ms_compare_facts(MsArena *arena, const MsFactModel *base, const MsFactModel *head, const MsDiffInput *input);

#endif
