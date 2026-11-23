# `ms profile` end to end on this platform: builds a program that burns CPU in a recursive function, runs it under the
# sampler and checks the bundle and both reports: `cmake -DMS_C=<ms> -DWORK=<scratch dir> -P cmake/ProfileRun.cmake`.
# The LLVM tools come from TOOL_DIR, PATH, or Homebrew's keg-only prefixes on macOS, as in SmokeRun.cmake.
cmake_minimum_required(VERSION 3.25)
file(REMOVE_RECURSE "${WORK}")
file(MAKE_DIRECTORY "${WORK}")
# A recursive function, which the compiler cannot inline into `main`, so it shows as a frame of its own.
file(WRITE "${WORK}/busy.ms" "fn fib(n: Int) Int:
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)

fn main() Int:
    print(fib(34))
    return 0
")
file(WRITE "${WORK}/exit.ms" "fn main() Int:
    print(\"hello\")
    return 3
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
# Profiling at the highest rate gives enough samples from a short run on any tick.
set(ENV{MS_PROFILE_HZ} 10000)

function(expect_contains text needle what)
  string(FIND "${text}" "${needle}" at)
  if(at EQUAL -1)
    message(FATAL_ERROR "${what}: expected '${needle}' in:\n${text}")
  endif()
endfunction()

# Text mode: the report names the function and the bundle holds every file.
execute_process(COMMAND "${MS_C}" profile busy.ms --out-dir bundle --top 5 WORKING_DIRECTORY "${WORK}"
  RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "ms profile busy.ms exited with '${status}'\n${out}${err}")
endif()
expect_contains("${out}" "Showing top" "report")
expect_contains("${out}" "fib" "report")
expect_contains("${out}" "Profile bundle: bundle" "report")
foreach(file profile.folded profile.pb top.txt manifest.json)
  if(NOT EXISTS "${WORK}/bundle/${file}")
    message(FATAL_ERROR "the bundle has no ${file}")
  endif()
endforeach()
file(READ "${WORK}/bundle/profile.folded" folded)
expect_contains("${folded}" "# hz=" "profile.folded")
expect_contains("${folded}" "main;fib" "profile.folded")
file(READ "${WORK}/bundle/manifest.json" manifest)
expect_contains("${manifest}" "\"pprof\": \"profile.pb\"" "manifest.json")
file(SIZE "${WORK}/bundle/profile.pb" pprof_size)
if(pprof_size EQUAL 0)
  message(FATAL_ERROR "profile.pb is empty")
endif()

# The directory must be new.
execute_process(COMMAND "${MS_C}" profile busy.ms --out-dir bundle WORKING_DIRECTORY "${WORK}"
  RESULT_VARIABLE status ERROR_VARIABLE err)
if(NOT status EQUAL 1)
  message(FATAL_ERROR "a second profile into the same directory exited with '${status}', expected 1")
endif()
expect_contains("${err}" "profile directory must be new" "second profile")

# JSON mode: one document with the program's output and the ranked functions; the program's status is returned.
execute_process(COMMAND "${MS_C}" profile exit.ms --out-dir json-bundle --json WORKING_DIRECTORY "${WORK}"
  RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT status EQUAL 3)
  message(FATAL_ERROR "ms profile exit.ms exited with '${status}', expected the program's 3\n${out}${err}")
endif()
expect_contains("${out}" "\"command\": \"profile\"" "json")
expect_contains("${out}" "\"exit_code\": 3" "json")
expect_contains("${out}" "\"stdout\": \"hello\\n\"" "json")
expect_contains("${out}" "\"reason\": \"program_exit\"" "json")
expect_contains("${out}" "\"profile\": {" "json")

# A program that does not compile leaves no directory behind.
file(WRITE "${WORK}/bad.ms" "fn main() Int:\n    x: Int := \"no\"\n    return 0\n")
execute_process(COMMAND "${MS_C}" profile bad.ms --out-dir bad-bundle WORKING_DIRECTORY "${WORK}"
  RESULT_VARIABLE status ERROR_VARIABLE err)
if(NOT status EQUAL 1 OR EXISTS "${WORK}/bad-bundle")
  message(FATAL_ERROR "a failed build exited with '${status}' or left its directory\n${err}")
endif()
