# The process entry: msrt_start, the arguments, the exit and stop hooks.
add_library(ms_entry STATIC args.c start.c stop_hooks.c)
ms_target_defaults(ms_entry)
target_link_libraries(ms_entry PUBLIC ms_abi ms_base ms_sys ms_io ms_core uv)
