/* cli/help_text.h: the `ms help` texts, a table of pages.
 * Page 0 is the command list; the other pages are one command each, in help order. */
#ifndef MS_CLI_HELP_TEXT_H
#define MS_CLI_HELP_TEXT_H

#include <stddef.h>

typedef struct MsHelpPage {
  const char *name; /* "top" for the command list, otherwise the command */
  const char *text;
} MsHelpPage;

extern const MsHelpPage MS_HELP_PAGES[];
extern const size_t MS_HELP_PAGE_COUNT;

#endif
