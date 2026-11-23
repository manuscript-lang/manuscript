# Replays a recorded language-server session against `ms lsp` and compares every message it sends.
#   cmake -DMS_C=<ms> -DCASE=<dir> -DWORK=<dir> -P LspSession.cmake
# CASE holds `requests.jsonl` (one JSON message per line) and `expected.jsonl` (the messages the server sends, one per
# line). `$ROOT` in either names the case directory as a path and `$ROOT_URI` as a file URI. Set RECORD=1 to write
# `expected.jsonl` from the run instead of comparing.
cmake_minimum_required(VERSION 3.20)

file(MAKE_DIRECTORY ${WORK})
file(COPY ${CASE}/ DESTINATION ${WORK}/case)
set(ROOT ${WORK}/case)
set(ROOT_URI file://${ROOT})
if(NOT ROOT MATCHES "^/")
  set(ROOT_URI file:///${ROOT})
endif()

function(substitute text out)
  string(REPLACE "$ROOT_URI" "${ROOT_URI}" text "${text}")
  string(REPLACE "$ROOT" "${ROOT}" text "${text}")
  set(${out} "${text}" PARENT_SCOPE)
endfunction()

file(STRINGS ${CASE}/requests.jsonl lines)
set(input "")
foreach(line IN LISTS lines)
  if(line STREQUAL "")
    continue()
  endif()
  substitute("${line}" message)
  string(LENGTH "${message}" length)
  string(APPEND input "Content-Length: ${length}\r\n\r\n${message}")
endforeach()
file(WRITE ${WORK}/input.bin "${input}")

execute_process(COMMAND ${MS_C} lsp INPUT_FILE ${WORK}/input.bin OUTPUT_FILE ${WORK}/output.bin ERROR_VARIABLE errors
  RESULT_VARIABLE status)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "ms lsp exited with ${status}: ${errors}")
endif()

file(READ ${WORK}/output.bin output)
set(replies "")
set(rest "${output}")
while(NOT rest STREQUAL "")
  # file(READ) turns each CRLF into LF, so a header ends at a blank line.
  string(FIND "${rest}" "\n\n" end)
  if(end LESS 0 OR NOT rest MATCHES "^Content-Length: ([0-9]+)")
    break()
  endif()
  set(length ${CMAKE_MATCH_1})
  math(EXPR header "${end} + 2")
  string(SUBSTRING "${rest}" ${header} ${length} body)
  math(EXPR next "${header} + ${length}")
  string(SUBSTRING "${rest}" ${next} -1 rest)
  # The root is written back as it came, so recorded files do not hold this machine's paths.
  string(REPLACE "${ROOT_URI}" "$ROOT_URI" body "${body}")
  string(REPLACE "${ROOT}" "$ROOT" body "${body}")
  string(REGEX REPLACE "\"version\":\"[0-9][^\"]*\"}}}$" "\"version\":\"$VERSION\"}}}" body "${body}")
  string(APPEND replies "${body}\n")
endwhile()
if(NOT rest STREQUAL "")
  message(FATAL_ERROR "ms lsp wrote a malformed frame: ${rest}")
endif()

if(RECORD)
  file(WRITE ${CASE}/expected.jsonl "${replies}")
  return()
endif()
file(READ ${CASE}/expected.jsonl expected)
if(NOT replies STREQUAL expected)
  message(FATAL_ERROR "ms lsp replies differ\n--- expected\n${expected}\n--- actual\n${replies}")
endif()
