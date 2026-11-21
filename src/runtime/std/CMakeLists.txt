# Natives of the standard library modules, built on base and the vendored libraries.
add_library(ms_std_text STATIC unicode.c unicode_width.c)
ms_target_defaults(ms_std_text)
target_link_libraries(ms_std_text PUBLIC ms_base pcre2)
