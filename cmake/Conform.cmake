# The conformance corpus and the command fixtures, replayed against the ms built here. Nothing else is needed:
# the runners are Manuscript programs (tools/conform-run.ms, tools/command-fixtures.ms) and ms runs them.
# Called as: cmake -DMS=<built ms> -DSOURCE_DIR=<repo> [-DONLY=commands] [-DENFORCE=ON] -P Conform.cmake
# Programs build with the Debug backend (Cranelift): about 2x faster than Release across run and test, same counts.
# Prints `phase: passed/total` for parse, check, run and test, then `commands: passed/total`, and each failure.
# The command fixtures must all pass. The corpus phases are reported; ENFORCE makes any difference fail the run
# (turn it on when the port is complete).
foreach(required MS SOURCE_DIR)
  if(NOT ${required})
    message(FATAL_ERROR "conform: ${required} is not set")
  endif()
endforeach()

# Runs one runner and returns its `<name>: passed/total` line in `counted`, printing the failures it listed.
function(replay name)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env "MS=${MS}" CONFORM_BUILD_TYPE=Debug "${MS}" run ${ARGN}
    WORKING_DIRECTORY "${SOURCE_DIR}"
    OUTPUT_VARIABLE output
    ERROR_VARIABLE errors)
  string(REGEX MATCH "${name}: ([0-9]+)/([0-9]+)" total "${output}")
  set(passed "${CMAKE_MATCH_1}")
  set(expected "${CMAKE_MATCH_2}")
  if(NOT total)
    message(FATAL_ERROR "conform: no ${name} counts\n${errors}\n${output}")
  endif()
  # The runner prints only failures (with their expected and observed under CONFORM_DIFF=1) and the counts.
  string(STRIP "${output}" output)
  message("${output}")
  set(counted "${total}" PARENT_SCOPE)
  if(passed STREQUAL expected)
    set(matches ON PARENT_SCOPE)
  else()
    set(matches OFF PARENT_SCOPE)
  endif()
endfunction()

set(all_match ON)
if(NOT ONLY STREQUAL "commands")
  foreach(phase IN ITEMS parse check run test)
    replay(${phase} tools/conform-run.ms -- --phase ${phase})
    message("${counted}")
    if(NOT matches)
      set(all_match OFF)
    endif()
  endforeach()
endif()

replay(commands tools/command-fixtures.ms -- check)
message("${counted}")
if(NOT matches)
  message(FATAL_ERROR "conform: the command fixtures above do not match")
endif()
if(ENFORCE AND NOT all_match)
  message(FATAL_ERROR "conform: the corpus phases above do not match")
endif()
