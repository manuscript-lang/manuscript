# The process entry: msrt_start, the arguments, the exit and stop hooks.
add_library(ms_entry STATIC args.c profile.c start.c stop_hooks.c test_support.c)
ms_target_defaults(ms_entry)
target_link_libraries(ms_entry PUBLIC ms_abi ms_base ms_sys ms_io ms_core uv)

add_executable(profile_unit profile_unit.c)
ms_target_defaults(profile_unit)
target_link_libraries(profile_unit PRIVATE ms_entry)
add_test(NAME entry_profile COMMAND profile_unit)
