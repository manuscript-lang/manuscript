/* The driver: from a command line to the stages that serve it. */
#ifndef MS_DRIVER_H
#define MS_DRIVER_H

#include "ms/libms.h"

/* The stages a command needs, as a bit set of 1 << MsStage; 0 for an unknown command. */
unsigned ms_command_stages(const char *command);

/* True when every stage the command needs is implemented in C. */
bool ms_command_in_c(const MsStageTable *table, const char *command);

/* Runs `ms argv[1..]`. Commands whose stages are all in C run here; the rest are handed whole to
 * the Rust `ms` named by $MS_RUST_CLI, or `ms-rust` beside this executable. Returns the exit
 * status. MS_DRIVER_TRACE=1 prints the choice to stderr; MS_STAGES overrides the stage table. */
int ms_driver_main(int argc, char **argv);

#endif
