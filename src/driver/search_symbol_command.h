#ifndef MS_DRIVER_SEARCH_SYMBOL_COMMAND_H
#define MS_DRIVER_SEARCH_SYMBOL_COMMAND_H

/* Runs `ms search_symbol [<name or words>... | <path>] [--limit n] [--json]`: the standard modules, one page of the
 * standard library, or the symbols matching a name. `argv` holds the arguments after the command. */
int ms_search_symbol_command(int argc, char **argv);

#endif
