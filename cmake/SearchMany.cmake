# `ms search_symbol` over a folder of many .ms files searches all of them, in batches that share one standard-library
# check:
# `cmake -DMS_C=<ms> -DWORK=<scratch dir> -P cmake/SearchMany.cmake`.
cmake_minimum_required(VERSION 3.25)
file(REMOVE_RECURSE "${WORK}")
file(MAKE_DIRECTORY "${WORK}")
foreach(n RANGE 1 130)
  string(LENGTH "${n}" digits)
  string(REPEAT "0" 3 pad)
  string(SUBSTRING "${pad}${n}" ${digits} 3 name)
  file(WRITE "${WORK}/f${name}.ms" "fn probe_${name}() Void:\n    return\n")
endforeach()

function(search query out_text out_error)
  separate_arguments(words NATIVE_COMMAND "${query}")
  execute_process(COMMAND "${MS_C}" search_symbol ${words} WORKING_DIRECTORY "${WORK}" RESULT_VARIABLE status
    OUTPUT_VARIABLE text ERROR_VARIABLE error)
  if(NOT status EQUAL 0)
    message(FATAL_ERROR "search_symbol ${query} exited ${status}:\n${error}")
  endif()
  set(${out_text} "${text}" PARENT_SCOPE)
  set(${out_error} "${error}" PARENT_SCOPE)
endfunction()

# Every file matches and every file is searched: the total counts all 130, and nothing is left out.
search("probe_ --json" text error)
string(FIND "${text}" "\"project_total\": 130," at)
if(at EQUAL -1)
  message(FATAL_ERROR "expected 130 project matches:\n${text}")
endif()
if(NOT "${error}" STREQUAL "")
  message(FATAL_ERROR "unexpected notice:\n${error}")
endif()
