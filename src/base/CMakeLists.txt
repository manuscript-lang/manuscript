add_library(ms_base STATIC alloc.c sort.c arena.c bytes.c cstr.c desc.c dir.c env.c fatal.c file.c intern.c list.c map.c
  message.c ostext.c path.c process.c sha256.c float_parse.c float_table.c fmt.c fmt_float.c fmt_precision.c fmt_sink.c search.c strbuild.c strformat.c string.c table.c utf8.c)
ms_target_defaults(ms_base)
target_link_libraries(ms_base PUBLIC mimalloc uv)

# Unit tests of pure data structures only; the corpus is the gate (plan rule 2).
foreach(unit safe alloc value map)
  add_executable(${unit}_unit ${unit}_unit.c)
  ms_target_defaults(${unit}_unit)
  target_link_libraries(${unit}_unit PRIVATE ms_base)
  add_test(NAME base_${unit} COMMAND ${unit}_unit)
endforeach()
