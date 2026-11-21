add_executable(ms-c main.c phases.c check_command.c fmt_command.c snippet.c)
ms_target_defaults(ms-c)
target_link_libraries(ms-c PRIVATE ms_base ms_syntax ms_project ms_check)
