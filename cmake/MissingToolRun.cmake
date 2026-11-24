# A build whose LLVM tool cannot start ends with a message that names the tool and the setting, status 1, and no crash:
# `cmake -DMS_C=<ms> -DWORK=<scratch dir> -DPROGRAM=<a large program> -P cmake/MissingToolRun.cmake`. A program large enough for four modules builds them at once, each on
# its own thread, so a spawn that fails and leaves libuv's process-wide signal tree pointing at freed stack is hit.
cmake_minimum_required(VERSION 3.25)
file(MAKE_DIRECTORY "${WORK}")
set(ENV{MS_LLVM} none)
set(ENV{MS_OPT} "${WORK}/no-such-opt")
execute_process(COMMAND "${MS_C}" run "${PROGRAM}" WORKING_DIRECTORY "${WORK}" RESULT_VARIABLE status
  OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT status EQUAL 1)
  message(FATAL_ERROR "ms run with a missing opt exited with '${status}', expected 1\n${out}${err}")
endif()
if(NOT err MATCHES "cannot run opt.*MS_OPT")
  message(FATAL_ERROR "the error does not name opt and MS_OPT:\n${out}${err}")
endif()
