# Target helpers and the one warning set for every C target. Warnings are errors from the first commit; there
# is no exemption list.
set(MS_C_WARNINGS
  -Wall -Wextra -Wpedantic -Werror
  -Wconversion -Wsign-conversion -Wshadow -Wvla -Wcast-qual -Wcast-align
  -Wstrict-prototypes -Wmissing-prototypes -Wundef)

# Adds the warning set and the shared include root to a target.
function(ms_target_defaults target)
  target_compile_options(${target} PRIVATE ${MS_C_WARNINGS})
  target_include_directories(${target} PRIVATE "${CMAKE_SOURCE_DIR}/src")
endfunction()

# The Windows C runtime marks fopen and friends deprecated; the C code uses the portable names.
if(WIN32)
  add_compile_definitions(_CRT_SECURE_NO_WARNINGS)
endif()

# Generated sources (embedded data, signature tables, runtime paths) go here, never into src/.
set(MS_GEN "${CMAKE_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${MS_GEN}")

# Every target's sources are named relative to src/<dir>; a path that is already absolute (generated) stays as is.
function(ms_prefix_sources out dir)
  set(paths "")
  foreach(file IN LISTS ARGN)
    if(NOT IS_ABSOLUTE "${file}")
      set(file "${CMAKE_SOURCE_DIR}/src/${dir}/${file}")
    endif()
    list(APPEND paths "${file}")
  endforeach()
  set(${out} "${paths}" PARENT_SCOPE)
endfunction()

# ms_library(<name> <dir under src> SOURCES <files>... [LINK <libraries>...]): a static library with the warning set.
function(ms_library name dir)
  cmake_parse_arguments(PARSE_ARGV 2 arg "" "" "SOURCES;LINK")
  ms_prefix_sources(sources ${dir} ${arg_SOURCES})
  add_library(${name} STATIC ${sources})
  ms_target_defaults(${name})
  set_target_properties(${name} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/src/${dir}")
  target_link_libraries(${name} PUBLIC ${arg_LINK})
endfunction()

# ms_executable(<name> <dir under src> SOURCES <files>... [LINK <libraries>...])
function(ms_executable name dir)
  cmake_parse_arguments(PARSE_ARGV 2 arg "" "" "SOURCES;LINK")
  ms_prefix_sources(sources ${dir} ${arg_SOURCES})
  add_executable(${name} ${sources})
  ms_target_defaults(${name})
  set_target_properties(${name} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/src/${dir}")
  target_link_libraries(${name} PRIVATE ${arg_LINK})
endfunction()
