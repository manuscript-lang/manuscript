/* libms as one translation unit: compile this file and nothing else. Static helpers in different
 * files must therefore not share names. */
#include "base.c"
#include "token.c"
#include "lex.c"
#include "dump_base.c"
#include "parse.c"
#include "dump.c"
