# A standard output that cannot be written (a full disk behind `ms doc > file`) fails the command instead of leaving a
# truncated file behind a zero status: `cmake -DMS_C=<ms> -P cmake/StdoutFull.cmake`. Needs /dev/full, which Linux has.
cmake_minimum_required(VERSION 3.25)
foreach(command version doc "check --help")
  separate_arguments(words NATIVE_COMMAND "${command}")
  execute_process(COMMAND "${MS_C}" ${words} OUTPUT_FILE /dev/full RESULT_VARIABLE status ERROR_VARIABLE error)
  if(status EQUAL 0)
    message(FATAL_ERROR "ms ${command} succeeded with a standard output that cannot be written")
  endif()
  string(FIND "${error}" "cannot write to standard output" at)
  if(at EQUAL -1)
    message(FATAL_ERROR "ms ${command} did not say its output was incomplete:\n${error}")
  endif()
endforeach()
