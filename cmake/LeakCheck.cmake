# Requires that fixtures leave no heap block live at exit: `cmake -DMS_C=<ms> -DFIXTURES=<dir> -DNAMES=<a;b;...>
# -DWORK=<scratch dir> -P cmake/LeakCheck.cmake`. A name is a path under FIXTURES; one ending in `.test` runs the
# fixture's `test` blocks with `ms test`, any other builds the program and runs it. MS_FREE_AT_EXIT=1 keeps the
# main-exit drops and makes the runtime release its own tables (pipe cells, scheduler, net and http threads, streams),
# so a program that frees everything shows 0 in the `current` column of mimalloc's `allocated` row
# (MIMALLOC_SHOW_STATS=1). A nonzero count is a leak in the program, the compiler's drops or the runtime. For
# `ms test` the first `allocated` row is the test executable's and the second is the compiler's.
cmake_minimum_required(VERSION 3.25)
file(MAKE_DIRECTORY "${WORK}")
set(ENV{MS_FREE_AT_EXIT} 1)
set(ENV{MIMALLOC_SHOW_STATS} 1)
set(failures "")
foreach(name IN LISTS NAMES)
  string(REGEX REPLACE "\\.test$" "" path "${name}")
  get_filename_component(base "${path}" NAME)
  set(source "${WORK}/${base}.ms")
  file(COPY_FILE "${FIXTURES}/${path}.ms" "${source}")
  if(name MATCHES "\\.test$")
    execute_process(COMMAND "${MS_C}" test "${source}" WORKING_DIRECTORY "${WORK}" RESULT_VARIABLE status
      OUTPUT_VARIABLE out ERROR_VARIABLE err)
  else()
    execute_process(COMMAND "${MS_C}" build "${source}" -o "${WORK}/${base}.bin" WORKING_DIRECTORY "${WORK}"
      RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
    if(NOT status EQUAL 0)
      list(APPEND failures "${name}: build failed\n${out}${err}")
      continue()
    endif()
    execute_process(COMMAND "${WORK}/${base}.bin" WORKING_DIRECTORY "${WORK}" RESULT_VARIABLE status
      OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 120)
  endif()
  if(NOT status EQUAL 0)
    list(APPEND failures "${name}: exited with '${status}'\n${out}${err}")
    continue()
  endif()
  # The last column of the first `allocated` row is the live block bytes.
  string(REGEX MATCH "(^|\n) *allocated *:[^\n]*" row "${err}")
  if(row STREQUAL "")
    string(LENGTH "${err}" err_length)
    string(LENGTH "${out}" out_length)
    string(SUBSTRING "${err}" 0 600 err_head)
    string(SUBSTRING "${out}" 0 600 out_head)
    list(APPEND failures "${name}: the allocator printed no statistics (exit status '${status}', ${err_length} bytes of error output, ${out_length} of output)\nerror: ${err_head}\noutput: ${out_head}")
    continue()
  endif()
  string(REGEX MATCH "[0-9][0-9.]*( *[KMG]i?B)? *$" current "${row}")
  string(STRIP "${current}" current)
  if(NOT current STREQUAL "0")
    string(STRIP "${row}" row)
    list(APPEND failures "${name}: ${current} still allocated at exit\n  ${row}")
  endif()
endforeach()
if(failures)
  string(REPLACE ";" "\n" report "${failures}")
  message(FATAL_ERROR "leaks:\n${report}")
endif()
