#ifndef MS_CLI_DOC_COMMAND_H
#define MS_CLI_DOC_COMMAND_H

/* Runs `ms dev doc`: the documentation snapshot of the bundled standard library as JSON, the input of tools/docgen.ms.
 * `argv` holds the arguments after the command. */
int ms_doc_command(int argc, char **argv);

#endif
