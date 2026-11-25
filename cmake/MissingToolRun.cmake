# A build whose LLVM library cannot load ends with a message that names the setting, status 1, and no crash:
# `cmake -DMS_C=<ms> -DWORK=<scratch dir> -DPROGRAM=<a large program> -P cmake/MissingToolRun.cmake`. A program large enough for four modules builds them at once, each on
# its own thread, so a failure that leaves libuv's process-wide state pointing at freed stack is hit.
cmake_minimum_required(VERSION 3.25)
file(MAKE_DIRECTORY "${WORK}")
# Debug builds use Cranelift when it is installed; turn it off so the build needs LLVM.
set(ENV{MS_CRANELIFT} off)
set(ENV{MS_LLVM} "${WORK}/no-such-libLLVM")
execute_process(COMMAND "${MS_C}" run "${PROGRAM}" WORKING_DIRECTORY "${WORK}" RESULT_VARIABLE status
  OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT status EQUAL 1)
  message(FATAL_ERROR "ms run with a missing LLVM library exited with '${status}', expected 1\n${out}${err}")
endif()
if(NOT err MATCHES "cannot load the LLVM library.*MS_LLVM")
  message(FATAL_ERROR "the error does not name the LLVM library and MS_LLVM:\n${out}${err}")
endif()
