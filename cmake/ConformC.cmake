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

set(totals "")
# run, check and test skip programs tagged `aliasing`; parse replays every fixture (same split as the Rust gate).
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

message("conform-c results")
foreach(counted IN LISTS totals)
  message("${counted}")
endforeach()

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
message("${command_total}")
