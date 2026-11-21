add_library(ms_core STATIC context.c stack.c timers.c queue.c)
ms_target_defaults(ms_core)
target_link_libraries(ms_core PUBLIC ms_sys ms_base)

# Unit test of pure data structures only; the corpus is the gate (plan rule 2).
add_executable(core_unit core_unit.c)
ms_target_defaults(core_unit)
target_link_libraries(core_unit PRIVATE ms_core)
add_test(NAME core_unit COMMAND core_unit)
