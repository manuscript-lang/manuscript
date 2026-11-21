add_library(ms_base STATIC alloc.c arena.c bytes.c cstr.c desc.c fatal.c intern.c list.c map.c strbuild.c string.c table.c)
ms_target_defaults(ms_base)

# Unit tests of pure data structures only; the corpus is the gate (plan rule 2).
foreach(unit safe alloc value map)
  add_executable(${unit}_unit ${unit}_unit.c)
  ms_target_defaults(${unit}_unit)
  target_link_libraries(${unit}_unit PRIVATE ms_base)
  add_test(NAME base_${unit} COMMAND ${unit}_unit)
endforeach()
