# The folder holding the pinned C libraries for a target triple (include/, lib/lib*.a), built once per target by
# src/runtime/third_party/build.sh. Shared by cmake/BuildRuntime.cmake (the runtime archive) and cmake/MsCompiler.cmake (libms
# without the runtime), so both link the same builds and no platform depends on what the machine has installed.
#   ms_pinned_libs_prefix(<triple> <c compiler> <out variable>)
function(ms_pinned_libs_prefix triple compiler out)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env MS_C_LIBS=pinned "CC=${compiler}" sh "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../src/runtime/third_party/build.sh" "${triple}"
    OUTPUT_VARIABLE prefix
    RESULT_VARIABLE status)
  if(NOT status EQUAL 0)
    message(FATAL_ERROR "build.sh failed (the C build needs cmake and ninja: `sh src/runtime/third_party/libs.sh install`)")
  endif()
  string(STRIP "${prefix}" prefix)
  # build.sh runs under MSYS2 on Windows and prints /d/a/x; CMake and the compiler read D:/a/x.
  if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows" AND prefix MATCHES "^/([A-Za-z])/(.*)$")
    string(TOUPPER "${CMAKE_MATCH_1}" drive)
    set(prefix "${drive}:/${CMAKE_MATCH_2}")
  endif()
  set(${out} "${prefix}" PARENT_SCOPE)
endfunction()
