/* tooling/html.h: the interactive page of `ms diagram --format html`: one self-contained HTML file that embeds the fact
 * model. Port of crates/ms-tooling/src/html.rs. */
#ifndef MS_TOOLING_HTML_H
#define MS_TOOLING_HTML_H

#include "tooling/facts.h"
#include "tooling/review.h"

/* Appends the page. `changes` are a diff's findings (NULL for none): the page marks those entities and lists what
 * changed. Identifier type hints are not collected yet, so the page shows none. */
void ms_html_page(MsArena *arena, const MsFactModel *model, const MsFindings *changes, MsStrBuild *out);

#endif
