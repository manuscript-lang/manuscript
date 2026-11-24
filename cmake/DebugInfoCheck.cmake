# Builds a Debug program with ms and stops it in a debugger at a function: the debugger must find the function by its
# source name and show its parameters and the caller's source line. `cmake -DMS_C=<ms> -DWORK=<scratch dir>
# -DTOOL_DIR=<llvm tools> -P cmake/DebugInfoCheck.cmake`. Uses lldb when found, otherwise gdb; with neither the test fails.
cmake_minimum_required(VERSION 3.25)
file(MAKE_DIRECTORY "${WORK}")
file(WRITE "${WORK}/probe.ms" "fn work(a Int, b Int) Int:
    var t = 0
    for i in 0..a:
        t += i * b + a
        t += i % 7
        t += i * i - b
        if t > 1000000: t = t / 3
    return t

fn main() Int:
    c := work(40, 5)
    print(f\"{c}\")
    return 0
")
if(WIN32)
  set(separator ";")
  set(exe ".exe")
else()
  set(separator ":")
  set(exe "")
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
execute_process(COMMAND "${MS_C}" build --build-type debug -o "${WORK}/probe${exe}" "${WORK}/probe.ms"
  WORKING_DIRECTORY "${WORK}" RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "ms build probe.ms exited with '${status}'\n${out}${err}")
endif()
find_program(DEBUGGER NAMES lldb gdb REQUIRED)
get_filename_component(debugger_name "${DEBUGGER}" NAME_WE)
if(debugger_name STREQUAL "lldb")
  set(commands -b -o "breakpoint set -n work" -o run -o "frame variable" -o bt "${WORK}/probe${exe}")
else()
  set(commands -batch -ex "break work" -ex run -ex "info args" -ex bt "${WORK}/probe${exe}")
endif()
execute_process(COMMAND "${DEBUGGER}" ${commands} WORKING_DIRECTORY "${WORK}" RESULT_VARIABLE status
  OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 120)
foreach(expected "a = 40" "b = 5" "probe.ms:11")
  string(FIND "${out}${err}" "${expected}" at)
  if(at LESS 0)
    message(FATAL_ERROR "${debugger_name} did not show '${expected}' stopped in work:\n${out}${err}")
  endif()
endforeach()
