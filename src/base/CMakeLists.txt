add_library(ms_base STATIC alloc.c arena.c bytes.c cstr.c desc.c env.c fatal.c file.c intern.c list.c map.c
  message.c ostext.c path.c process.c float_parse.c float_table.c fmt.c fmt_float.c fmt_precision.c fmt_sink.c search.c strbuild.c strformat.c string.c table.c utf8.c)
if(WIN32)
  target_sources(ms_base PRIVATE file_windows.c ostext_windows.c process_windows.c)
else()
  target_sources(ms_base PRIVATE file_posix.c process_posix.c)
endif()
ms_target_defaults(ms_base)

# Unit tests of pure data structures only; the corpus is the gate (plan rule 2).
foreach(unit safe alloc value map)
  add_executable(${unit}_unit ${unit}_unit.c)
  ms_target_defaults(${unit}_unit)
  target_link_libraries(${unit}_unit PRIVATE ms_base)
  add_test(NAME base_${unit} COMMAND ${unit}_unit)
endforeach()
