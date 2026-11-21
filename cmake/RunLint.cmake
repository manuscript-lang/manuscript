# Lists the repository's files for ms_lint, then runs it.
cmake_policy(SET CMP0009 NEW)
# Called as: cmake -DMS_LINT=<ms_lint> -DSOURCE_DIR=<repo> -DLIST_FILE=<out> -P RunLint.cmake
file(GLOB_RECURSE found RELATIVE "${SOURCE_DIR}"
  "${SOURCE_DIR}/src/*" "${SOURCE_DIR}/cmake/*" "${SOURCE_DIR}/.github/*"
  "${SOURCE_DIR}/tools/*" "${SOURCE_DIR}/toolchain/*" "${SOURCE_DIR}/bench/*"
  "${SOURCE_DIR}/extensions/*" "${SOURCE_DIR}/website/*" "${SOURCE_DIR}/examples/*"
  "${SOURCE_DIR}/documentation/*" "${SOURCE_DIR}/skills/*" "${SOURCE_DIR}/*.sh" "${SOURCE_DIR}/*.py")
list(FILTER found EXCLUDE REGEX "(^|/)(node_modules|target|\\.artifacts)/")
string(REPLACE ";" "\n" listing "${found}")
file(WRITE "${LIST_FILE}" "${listing}\n")
execute_process(COMMAND "${MS_LINT}" "${SOURCE_DIR}" "${LIST_FILE}" RESULT_VARIABLE status)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "ms_lint failed (status ${status})")
endif()
