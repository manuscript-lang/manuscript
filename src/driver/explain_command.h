/* driver/explain_command.h: `ms explain <code>... [--json]`. */
#ifndef MS_DRIVER_EXPLAIN_COMMAND_H
#define MS_DRIVER_EXPLAIN_COMMAND_H

/* `argv` holds the arguments after the command. Returns the process status. */
int ms_explain_command(int argc, char **argv);

#endif
