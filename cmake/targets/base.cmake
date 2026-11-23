ms_library(ms_base base
  SOURCES
    duration.c alloc.c sort.c arena.c bytes.c cstr.c desc.c dir.c env.c fatal.c file.c intern.c list.c map.c
    message.c ostext.c path.c path_rules.c process.c sha256.c float_parse.c float_table.c fmt.c fmt_float.c
    fmt_precision.c fmt_sink.c search.c strbuild.c strformat.c string.c table.c utf8.c wide.c
  LINK mimalloc uv)

# Unit tests of pure data structures only; the corpus is the gate.
foreach(unit safe alloc value map)
  ms_executable(${unit}_unit base SOURCES ${unit}_unit.c LINK ms_base)
  add_test(NAME base_${unit} COMMAND ${unit}_unit)
endforeach()
