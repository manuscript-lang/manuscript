add_executable(ms-c backend.c main.c phases.c check_command.c fmt_command.c fmt_targets.c package_commands.c package_fetch.c package_git.c package_validate.c snippet.c)
ms_target_defaults(ms-c)
target_link_libraries(ms-c PRIVATE ms_base ms_syntax ms_project ms_check ms_own ms_lower ms_mir ms_opt ms_emit)
