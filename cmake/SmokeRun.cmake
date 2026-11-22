# Builds and runs a one-line program with ms-c on this platform, the check that packaging, the pipeline and the
# linker work together: `cmake -DMS_C=<ms-c> -DWORK=<scratch dir> -P cmake/SmokeRun.cmake`. The program's exit
# status must be 7. The LLVM tools (opt, llc, lld) come from PATH, or from Homebrew's keg-only prefixes on macOS.
cmake_minimum_required(VERSION 3.25)
file(MAKE_DIRECTORY "${WORK}")
file(WRITE "${WORK}/smoke.ms" "fn main() Int:\n    return 7\n")
set(path "$ENV{PATH}")
foreach(prefix /opt/homebrew/opt/llvm /usr/local/opt/llvm /opt/homebrew/opt/lld /usr/local/opt/lld)
  if(IS_DIRECTORY "${prefix}/bin")
    set(path "${prefix}/bin:${path}")
  endif()
endforeach()
set(ENV{PATH} "${path}")
execute_process(COMMAND "${MS_C}" run "${WORK}/smoke.ms" WORKING_DIRECTORY "${WORK}" RESULT_VARIABLE status
  OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT status EQUAL 7)
  message(FATAL_ERROR "ms-c run smoke.ms exited with '${status}', expected 7\n${out}${err}")
endif()
