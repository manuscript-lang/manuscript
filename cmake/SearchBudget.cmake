# `ms search_symbol` over a folder with more .ms files than its budget: it answers from the first files in name order and
# says so, instead of spending a check per file on the whole tree:
# `cmake -DMS_C=<ms> -DWORK=<scratch dir> -P cmake/SearchBudget.cmake`.
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

# Every file matches; the total counts only the 120 searched, and the answer says the tree was cut.
search("probe_ --json" text error)
string(FIND "${text}" "\"project_total\": 120," at)
if(at EQUAL -1)
  message(FATAL_ERROR "expected 120 project matches:\n${text}")
endif()
string(FIND "${error}" "searched the first 120 .ms files" at)
if(at EQUAL -1)
  message(FATAL_ERROR "no notice that the search was cut:\n${error}")
endif()
string(FIND "${error}" "narrower folder" at)
if(at EQUAL -1)
  message(FATAL_ERROR "no hint to narrow the folder:\n${error}")
endif()
