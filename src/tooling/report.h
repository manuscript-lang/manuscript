/* tooling/report.h: the review report, fixed templates filled with checker facts. Port of the project half of
 * crates/ms-tooling/src/report.rs. */
#ifndef MS_TOOLING_REPORT_H
#define MS_TOOLING_REPORT_H

#include "tooling/facts.h"
#include "tooling/review.h"

enum { MS_REPORT_FORMAT = 2 };

typedef struct MsSection {
  MsSpan title;
  MsSpans headers;
  MsSpans cells; /* rows of headers.len cells, flat */
  MsSpans lines;
  size_t more;
} MsSection;
MS_AVEC(MsSections, ms_sections, MsSection)

typedef struct MsReport {
  MsSpan mode, input, result;
  MsSections sections;
  MsSpan digest;
  MsFindings findings;
  bool has_base; /* diff mode: `base_checked` is present */
  bool base_checked;
} MsReport;

typedef struct MsReviewOptions {
  bool all;
  MsSpan effect;
} MsReviewOptions;

MsReport ms_project_report(MsArena *arena, const MsFactModel *head, MsReviewOptions options);

/* The report of a change: head facts, base facts and the input. */
MsReport ms_diff_report(MsArena *arena, const MsFactModel *base, const MsFactModel *head, const MsDiffInput *input,
                        MsReviewOptions options);

/* One finding in full, or its JSON document. False leaves the reason in `error`. */
bool ms_review_explain(MsArena *arena, const MsFindings *findings, const MsFactModel *head, MsSpan selector, MsStrBuild *out,
                MsSpan *error);
bool ms_review_explain_json(MsArena *arena, const MsFindings *findings, const MsFactModel *head, MsSpan selector, MsStrBuild *out,
                     MsSpan *error);

/* `ascii`, `markdown` or `json`, ending in a newline. */
void ms_report_render(MsArena *arena, const MsReport *report, MsSpan format, MsStrBuild *out);

#endif
