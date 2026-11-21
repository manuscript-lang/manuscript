# Natives of the standard library modules, built on base and the vendored libraries.
add_library(ms_std_text STATIC
  regex_abi.c
  regex_engine.c
  regex_replace.c
  regex_scan.c
  regex_screen.c
  regex_text.c
  unicode.c
  unicode_width.c)
ms_target_defaults(ms_std_text)
target_link_libraries(ms_std_text PUBLIC ms_base ms_values pcre2)

# @std/data/json: the scanner, the document handle, the tree builder and the writer.
add_library(ms_std_data STATIC
  json_doc.c
  json_scalar.c
  json_scan.c
  json_tree.c
  json_write.c)
ms_target_defaults(ms_std_data)
target_link_libraries(ms_std_data PUBLIC ms_base ms_values)
