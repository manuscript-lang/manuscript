/* compiler/check/message_fixes.h: machine-applicable fixes named by a diagnostic's own message.
 *
 * A diagnostic that ends in `; did you mean 'x'?` also carries the edit that replaces the word at its position
 * with `x`, unless a pass already attached a fix; an import diagnostic carries none. */
#ifndef MS_COMPILER_CHECK_MESSAGE_FIXES_H
#define MS_COMPILER_CHECK_MESSAGE_FIXES_H

#include "compiler/check/program.h"

void ms_check_attach_message_fixes(MsCheckProgram *program);

#endif
