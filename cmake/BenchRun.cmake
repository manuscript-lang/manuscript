# `ms bench` end to end on this platform: runs a real bench block and checks the report's shape, not its timings, plus the
# failure and listing paths: `cmake -DMS_C=<ms> -DWORK=<scratch dir> -P cmake/BenchRun.cmake`.
cmake_minimum_required(VERSION 3.25)
file(REMOVE_RECURSE "${WORK}")
file(MAKE_DIRECTORY "${WORK}")
file(WRITE "${WORK}/sum_bench.ms" "import keep, measure, opaque from \"@std/test/bench.ms\"

bench \"sum_to_1000\":
    fn work() Result[Void, Error]:
        var total = 0
        for i in 0..opaque(1000):
            total += i
        return keep(total)

    measure(1000, work)?
")
if(WIN32)
  set(separator ";")
else()
  set(separator ":")
endif()
set(path "$ENV{PATH}")
if(TOOL_DIR)
  set(path "${TOOL_DIR}${separator}${path}")
endif()
foreach(prefix /opt/homebrew/opt/llvm /usr/local/opt/llvm /opt/homebrew/opt/lld /usr/local/opt/lld)
  if(IS_DIRECTORY "${prefix}/bin")
    set(path "${prefix}/bin${separator}${path}")
  endif()
endforeach()
set(ENV{PATH} "${path}")

function(expect_contains text needle what)
  string(FIND "${text}" "${needle}" at)
  if(at EQUAL -1)
    message(FATAL_ERROR "${what}: expected '${needle}' in:\n${text}")
  endif()
endfunction()

execute_process(COMMAND "${MS_C}" bench sum_bench.ms --time 1ms --samples 2 --json WORKING_DIRECTORY "${WORK}"
  RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "ms bench exited with '${status}'\n${out}${err}")
endif()
expect_contains("${out}" "sum_to_1000" "json")
expect_contains("${out}" "\"stats\"" "json")
expect_contains("${out}" "\"median_ns\"" "json")
# The work has to be timed: a body over constants must not be folded away by the optimizer (keep is a barrier).
string(REGEX MATCH "\"median_ns\": *([0-9.eE+-]+)" unused "${out}")
set(median "${CMAKE_MATCH_1}")
if(median STREQUAL "" OR median MATCHES "^0(\\.0*)?$")
  message(FATAL_ERROR "the bench reported a median of '${median}' ns: its work was optimized away\n${out}")
endif()

execute_process(COMMAND "${MS_C}" bench sum_bench.ms --list WORKING_DIRECTORY "${WORK}"
  RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "ms bench --list exited with '${status}'\n${out}${err}")
endif()
expect_contains("${out}" "sum_to_1000" "list")
