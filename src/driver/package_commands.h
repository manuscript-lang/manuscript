/* driver/package_commands.h: `ms install`, `ms add` and `ms remove`: resolve `[dependencies]`, download them with git,
 * and write `ms.lock`. These are the only commands that use the network. Port of crates/ms-cli/src/fetch.rs. */
#ifndef MS_DRIVER_PACKAGE_COMMANDS_H
#define MS_DRIVER_PACKAGE_COMMANDS_H

/* Each takes the arguments after the command and returns the process status (0, or 1 for an error). */
int ms_install_command(int argc, char **argv);
int ms_add_command(int argc, char **argv);
int ms_remove_command(int argc, char **argv);

#endif
