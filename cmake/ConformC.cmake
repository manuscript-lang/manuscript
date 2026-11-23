# Runs the frozen conformance corpus against ms-c and prints `phase: passed/total` per phase.
# Called as: cmake -DMS_CONFORM=<oracle ms-conform> -DMS_C=<ms-c> -DSOURCE_DIR=<repo> -P ConformC.cmake
# Extra selection (for example a layer's subset): -DEXTRA="--tag;tier-core".
# ms-conform is the frozen oracle runner from 660429d4; it is not part of the C build.
foreach(required MS_CONFORM MS_C SOURCE_DIR)
  if(NOT ${required})
    message(FATAL_ERROR "conform-c: ${required} is not set (see src/README.md, Oracle)")
  endif()
endforeach()
if(NOT EXISTS "${MS_CONFORM}")
  message(FATAL_ERROR "conform-c: oracle runner not found: ${MS_CONFORM}")
endif()

# -DONLY=commands skips the corpus phases and replays the command fixtures alone, printing each failure.
set(totals "")
if(NOT ONLY STREQUAL "commands")
# run, check and test skip programs tagged `aliasing`; parse replays every fixture (same split as the Rust gate).
if(NOT RUNNER STREQUAL "ms")
foreach(pass IN ITEMS "run,check,test;--exclude-tag;aliasing" "parse")
  list(GET pass 0 phases)
  list(REMOVE_AT pass 0)
  execute_process(
    COMMAND "${MS_CONFORM}" run --ms "${MS_C}" --phase "${phases}" --quiet ${pass} ${EXTRA}
    WORKING_DIRECTORY "${SOURCE_DIR}"
    OUTPUT_VARIABLE output
    ERROR_VARIABLE errors
    RESULT_VARIABLE status)
  string(REGEX MATCHALL "\n  (parse|check|run|test) +[0-9]+/[0-9]+" lines "\n${output}")
  if(NOT lines)
    message(FATAL_ERROR "conform-c: no phase counts from ms-conform (status ${status})\n${errors}\n${output}")
  endif()
  foreach(line IN LISTS lines)
    string(REGEX REPLACE "^\n  ([a-z]+) +([0-9]+/[0-9]+)$" "\\1: \\2" counted "${line}")
    list(APPEND totals "${counted}")
  endforeach()
endforeach()

endif()
# -DRUNNER=ms replays the corpus with tools/conform-run.ms (on the oracle ms) instead of the frozen
# Rust runner; both must give the same counts before the Rust runner is dropped.
if(RUNNER STREQUAL "ms" AND NOT ONLY STREQUAL "commands")
  set(totals "")
  get_filename_component(runner_dir "${MS_CONFORM}" DIRECTORY)
  foreach(phase IN ITEMS parse check run test)
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E env "MS=${MS_C}" "${runner_dir}/ms${CMAKE_EXECUTABLE_SUFFIX}"
        run tools/conform-run.ms -- --phase ${phase} ${EXTRA}
      WORKING_DIRECTORY "${SOURCE_DIR}"
      OUTPUT_VARIABLE runner_output
      ERROR_VARIABLE runner_errors)
    string(REGEX MATCH "${phase}: [0-9]+/[0-9]+" counted "${runner_output}")
    if(NOT counted)
      message(FATAL_ERROR "conform-c: no ${phase} counts from conform-run.ms\n${runner_errors}\n${runner_output}")
    endif()
    list(APPEND totals "${counted}")
  endforeach()
endif()

message("conform-c results")
foreach(counted IN LISTS totals)
  message("${counted}")
endforeach()
endif()

# Command fixtures (tests/conformance/commands): replayed by the Manuscript runner on the oracle ms,
# with the ms under test named by MS.
get_filename_component(oracle_dir "${MS_CONFORM}" DIRECTORY)
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env "MS=${MS_C}" "${oracle_dir}/ms${CMAKE_EXECUTABLE_SUFFIX}"
    run tools/command-fixtures.ms -- check ${COMMAND_EXTRA}
  WORKING_DIRECTORY "${SOURCE_DIR}"
  OUTPUT_VARIABLE command_output
  ERROR_VARIABLE command_errors)
string(REGEX MATCH "commands: [0-9]+/[0-9]+" command_total "${command_output}")
if(NOT command_total)
  message(FATAL_ERROR "conform-c: no command counts\n${command_errors}\n${command_output}")
endif()
if(ONLY STREQUAL "commands")
  message("${command_output}")
endif()
message("${command_total}")
# A commands-only replay is a pass or fail check: every fixture must match.
if(ONLY STREQUAL "commands")
  string(REGEX MATCH "commands: ([0-9]+)/([0-9]+)" ignored "${command_total}")
  if(NOT CMAKE_MATCH_1 STREQUAL CMAKE_MATCH_2)
    message(FATAL_ERROR "conform-c: ${command_total}: the command fixtures above do not match")
  endif()
endif()
