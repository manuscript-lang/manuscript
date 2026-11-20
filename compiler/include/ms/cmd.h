/* Commands whose own logic is in C, one command at a time (the TOOL stage of the stage table). A command
 * returns MS_CMD_HANDOVER when it meets a request it does not cover, before it has printed anything; the
 * driver then hands the whole command line to the Rust `ms`. */
#ifndef MS_CMD_H
#define MS_CMD_H

#define MS_CMD_HANDOVER (-1)

/* `ms check FILE.ms [--json]`; argv[0] is the command name. */
int ms_cmd_check(int argc, char **argv);

#endif
