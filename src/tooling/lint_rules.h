/* tooling/lint_rules.h: the lint rules `ms lint` can report and `ms explain` describes. */
#ifndef MS_TOOLING_LINT_RULES_H
#define MS_TOOLING_LINT_RULES_H

#include <stddef.h>

#include "base/safe.h"

/* Warnings are reported without failing `ms lint`; errors fail it. */
typedef enum MsLintSeverity { MS_LINT_WARNING, MS_LINT_ERROR } MsLintSeverity;

typedef struct MsLintRule {
  const char *code, *family;
  MsLintSeverity severity;
  const char *repair;
} MsLintRule;

extern const MsLintRule MS_LINT_RULES[];
extern const size_t MS_LINT_RULE_COUNT;

/* The rule for `code`, matched case-insensitively, or NULL. */
const MsLintRule *ms_lint_rule(MsSpan code);

#endif
