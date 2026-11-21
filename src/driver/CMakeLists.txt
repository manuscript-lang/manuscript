add_executable(ms-c main.c phases.c fmt_command.c)
ms_target_defaults(ms-c)
target_link_libraries(ms-c PRIVATE ms_base ms_syntax)
