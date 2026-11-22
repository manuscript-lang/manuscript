/* compiler/check/names_habit.h: hints for names borrowed from other languages. */
#ifndef MS_COMPILER_CHECK_NAMES_HABIT_H
#define MS_COMPILER_CHECK_NAMES_HABIT_H

#include "base/safe.h"
#include "base/strbuild.h"

/* When `name` is a known habit, appends its hint (without the leading "; ") and sets `*edit` to the spelling
 * that replaces it, or NULL. */
bool ms_name_habit(MsSpan name, MsStrBuild *hint, const char **edit);

#endif
