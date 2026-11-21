# The C half of the runtime archive: every source of src/runtime/{sys,core,io,net,std} for this target, compiled to
# objects, plus every member of the static libraries those sources include. The target `ms_runtime` leaves
#   c-objects.txt   one path per line: our objects and the library members, which `ar` adds to the runtime archive
#   c-features.txt  which optional parts the archive has (reactor), which the Rust build then leaves out
# in the build folder. The linker takes a member only when a program reaches it.
set(MS_RUNTIME_LAYERS sys core io entry net std)

# The library names (as MS_LIB_NAMES and llhttp) whose headers `source` includes, directly or through a header
# of its own folder.
function(ms_libraries_of source out)
  file(READ "${source}" _text)
  get_filename_component(_dir "${source}" DIRECTORY)
  string(REGEX MATCHALL "#include \"[^\"]+\"" _locals "${_text}")
  foreach(_local ${_locals})
    string(REGEX REPLACE "#include \"([^\"]+)\"" "\\1" _header "${_local}")
    if(EXISTS "${_dir}/${_header}")
      file(READ "${_dir}/${_header}" _more)
      string(APPEND _text "${_more}")
    endif()
  endforeach()
  set(_found "")
  foreach(_rule "<uv.h>=uv" "<llhttp.h>=llhttp" "<mimalloc.h>=mimalloc" "<nghttp2/=nghttp2" "<openssl/=ssl;crypto" "<pcre2.h>=pcre2" "<zlib.h>=z" "<curl/=curl")
    string(REGEX MATCH "^([^=]*)=(.*)$" _unused "${_rule}")
    string(FIND "${_text}" "#include ${CMAKE_MATCH_1}" _at)
    if(NOT _at EQUAL -1)
      list(APPEND _found ${CMAKE_MATCH_2})
    endif()
  endforeach()
  set(${out} "${_found}" PARENT_SCOPE)
endfunction()

set(_sources "")
foreach(layer ${MS_RUNTIME_LAYERS})
  file(GLOB_RECURSE _layer CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/src/runtime/${layer}/*.c")
  list(APPEND _sources ${_layer})
endforeach()
list(SORT _sources)

set(_selected "")
set(_used_libs "")
foreach(source ${_sources})
  file(RELATIVE_PATH _rel "${CMAKE_SOURCE_DIR}/src/runtime" "${source}")
  string(REPLACE "/" ";" _parts "${_rel}")
  set(_skip OFF)
  foreach(part ${_parts})
    if(part IN_LIST MS_ALL_PLATFORM_DIRS AND NOT part IN_LIST MS_PLATFORM_DIRS)
      set(_skip ON)
    endif()
  endforeach()
  if(_skip)
    continue()
  endif()
  # The glibc process entry belongs to the archive programs link, which has no crt1.o; a test binary has one.
  if(_rel STREQUAL "sys/glibc/start.c" AND NOT MS_PROCESS_ENTRY)
    continue()
  endif()
  ms_libraries_of("${source}" _needs)
  set(_missing OFF)
  foreach(lib ${_needs})
    if(NOT MS_LIBS_WIRED AND NOT lib IN_LIST MS_LIBS_ONLY)
      set(_missing ON)
    endif()
  endforeach()
  if(_missing)
    continue()
  endif()
  list(APPEND _selected "${source}")
  list(APPEND _used_libs ${_needs})
  get_filename_component(_dir "${source}" DIRECTORY)
  set(_includes "${_dir}")
  foreach(lib ${_needs})
    if(lib STREQUAL "llhttp")
      list(APPEND _includes "${MS_LLHTTP_DIR}/include")
    elseif(lib STREQUAL "mimalloc")
      list(APPEND _includes "${MS_MIMALLOC_DIR}/include")
    else()
      list(APPEND _includes ${MS_LIB_${lib}_INCLUDES})
    endif()
  endforeach()
  list(REMOVE_DUPLICATES _includes)
  set_source_files_properties("${source}" PROPERTIES INCLUDE_DIRECTORIES "${_includes}")
endforeach()
list(REMOVE_DUPLICATES _used_libs)

set(_features "")
foreach(source ${_selected})
  get_filename_component(_name "${source}" NAME)
  # reactor.c defines the ms_io_* entry points; the files beside it (ring, refused) need no library and stay
  # selected on a target without libuv, which has no reactor.
  if(source MATCHES "/runtime/io/reactor\\.c$")
    list(APPEND _features reactor)
  endif()
endforeach()
list(REMOVE_DUPLICATES _features)
string(REPLACE ";" "\n" _features_text "${_features}")
file(WRITE "${CMAKE_BINARY_DIR}/c-features.txt" "${_features_text}\n")

if(NOT _selected)
  file(WRITE "${CMAKE_BINARY_DIR}/c-objects.txt" "")
  add_custom_target(ms_runtime)
  return()
endif()

add_library(ms_runtime_objects OBJECT ${_selected})
target_include_directories(ms_runtime_objects PRIVATE "${CMAKE_SOURCE_DIR}/src/runtime/include")
target_compile_options(ms_runtime_objects PRIVATE -O2 -Wall -Wextra -Werror ${MS_C_FLAGS})
target_compile_definitions(ms_runtime_objects PRIVATE ${MS_LIBS_DEFINES})
if(MS_ALLOC_STATS)
  target_compile_definitions(ms_runtime_objects PRIVATE MS_ALLOC_STATS)
endif()
if(MS_LIBS_IDIRAFTER)
  # MSYS2 keeps its headers in one prefix; llvm-mingw's own come first.
  target_compile_options(ms_runtime_objects PRIVATE -idirafter "${MS_LIBS_PREFIX}/include")
endif()

set(_archives "")
foreach(lib ${_used_libs})
  if(lib STREQUAL "llhttp")
    list(APPEND _archives "$<TARGET_FILE:ms_llhttp>")
  elseif(lib STREQUAL "mimalloc")
    list(APPEND _archives "$<TARGET_FILE:ms_mimalloc>")
  else()
    list(APPEND _archives ${MS_LIB_${lib}_ARCHIVES})
  endif()
endforeach()
list(REMOVE_DUPLICATES _archives)
set(_library_targets "")
if(TARGET ms_zlib)
  list(APPEND _library_targets ms_zlib)
endif()
file(GENERATE OUTPUT "${CMAKE_BINARY_DIR}/c-object-files.txt"
     CONTENT "$<JOIN:$<TARGET_OBJECTS:ms_runtime_objects>,\n>\n")
file(GENERATE OUTPUT "${CMAKE_BINARY_DIR}/c-library-files.txt" CONTENT "$<JOIN:${_archives},\n>\n")

add_custom_command(
  OUTPUT "${CMAKE_BINARY_DIR}/c-objects.txt"
  COMMAND ${CMAKE_COMMAND} -DAR=${CMAKE_AR} -DOBJECTS=${CMAKE_BINARY_DIR}/c-object-files.txt
          -DLIBRARIES=${CMAKE_BINARY_DIR}/c-library-files.txt -DWORK=${CMAKE_BINARY_DIR}/c-members
          -DOUT=${CMAKE_BINARY_DIR}/c-objects.txt -P ${CMAKE_SOURCE_DIR}/cmake/FoldArchives.cmake
  # The object files themselves, not the target: an OBJECT library has no output file, so a dependency on its name
  # would let the folded copies in c-members go stale after a source changes.
  DEPENDS $<TARGET_OBJECTS:ms_runtime_objects> ms_llhttp ${_library_targets} ms_mimalloc "${CMAKE_BINARY_DIR}/c-object-files.txt"
          "${CMAKE_BINARY_DIR}/c-library-files.txt" ${_archives}
          "${CMAKE_SOURCE_DIR}/cmake/FoldArchives.cmake"
  COMMENT "Folding the C libraries into the runtime objects"
  VERBATIM)
add_custom_target(ms_runtime ALL DEPENDS "${CMAKE_BINARY_DIR}/c-objects.txt")
