#ifndef MS_DRIVER_DIAGRAM_COMMAND_H
#define MS_DRIVER_DIAGRAM_COMMAND_H

/* Runs `ms diagram <file.ms|ms.toml> [--view v] [--entity e] [--depth n] [--diff f] [--format f] [-o file] [--json]`:
 * the static call graph as text, Mermaid, a scoped view or a page. `argv` holds the arguments after the command. */
int ms_diagram_command(int argc, char **argv);

#endif
