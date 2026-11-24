ms_executable(ms cli
  SOURCES
    install_layout.c pipeline.c backend.c emit_command.c diagram_command.c review_command.c search_symbol_command.c doc_command.c search_project.c
    fault_record.c inspect_command.c main.c phases.c check_command.c verify_command.c fmt_command.c
    check_fix.c check_selection.c display.c files.c fmt_targets.c fmt_labels.c init_command.c
    invocation.c invocation_rules.c build_type.c build_command.c run_command.c test_command.c test_document.c
    bench_command.c profile_command.c profile_folded.c test_options.c test_records.c test_run.c watch.c package_cache.c
    package_commands.c package_fetch.c package_git.c package_validate.c help_command.c help_text.c
    explain_command.c
  LINK ms_base ms_syntax ms_project ms_check ms_own ms_lower ms_mir ms_opt ms_emit ms_link ms_tooling ms_lsp ms_std_text)
file(STRINGS ${CMAKE_SOURCE_DIR}/.msversion MS_VERSION_TEXT LIMIT_COUNT 1)
target_compile_definitions(ms PRIVATE MS_VERSION="${MS_VERSION_TEXT}")

set(MS_MINGW_DIR "" CACHE PATH "llvm-mingw root for Windows links (default: the compiler's own prefix)")
include(MsRuntimePackage)
ms_add_musl_runtime()
ms_package_runtime(ms ms_runtime)
# The runtime archives of this project (not the vendored libraries): `cmake --preset stats` builds only these for the
# leak, cancel and count gates, which link programs with them and the ci build's compiler and vendored libraries.
ms_collect_archives(ms_runtime ms_runtime_archives)
list(FILTER ms_runtime_archives INCLUDE REGEX "^ms_")
add_custom_target(stats-runtime DEPENDS ${ms_runtime_archives})

# Build and run a one-line program: packaging, pipeline and linker together on this platform.
get_filename_component(MS_COMPILER_BIN "${CMAKE_C_COMPILER}" DIRECTORY)
add_test(NAME smoke_run COMMAND ${CMAKE_COMMAND} -DMS_C=$<TARGET_FILE:ms> -DWORK=${CMAKE_BINARY_DIR}/src/cli/smoke
  -DTOOL_DIR=${MS_COMPILER_BIN} -P ${CMAKE_SOURCE_DIR}/cmake/SmokeRun.cmake)
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  # The same program linked against musl (`--static`), the other Linux link path.
  add_test(NAME smoke_run_static COMMAND ${CMAKE_COMMAND} -DMS_C=$<TARGET_FILE:ms> -DRUN_FLAGS=--static
    -DWORK=${CMAKE_BINARY_DIR}/src/cli/smoke-static -DTOOL_DIR=${MS_COMPILER_BIN} -P ${CMAKE_SOURCE_DIR}/cmake/SmokeRun.cmake)
endif()

# A build whose opt cannot start fails with a message naming the tool and its setting, not a crash (#6843).
add_test(NAME missing_tool COMMAND ${CMAKE_COMMAND} -DMS_C=$<TARGET_FILE:ms> -DWORK=${CMAKE_BINARY_DIR}/src/cli/missing-tool
  -DPROGRAM=${CMAKE_SOURCE_DIR}/tools/repo-check.ms -P ${CMAKE_SOURCE_DIR}/cmake/MissingToolRun.cmake)

# A debugger stopped in a Debug build's function finds it by name and shows its parameters and the caller's line.
add_test(NAME debug_info COMMAND ${CMAKE_COMMAND} -DMS_C=$<TARGET_FILE:ms> -DWORK=${CMAKE_BINARY_DIR}/src/cli/debug-info
  -DTOOL_DIR=${MS_COMPILER_BIN} -P ${CMAKE_SOURCE_DIR}/cmake/DebugInfoCheck.cmake)

# Fixtures that own resources, fault, recurse deeply or start threads leave nothing allocated at exit with the process-exit
# frees kept (cmake/LeakCheck.cmake); a test that fails here found a leak, not a stale baseline.
set(MS_LEAK_FIXTURES accept/bind-collection-resource-read-in-place accept/interface-box-freed-with-resource
  stdlib/net-close-releases-socket
  accept/call-depth.test accept/faulting-close-in-list-releases-buffer.test accept/pipe-flow.test
  stdlib/promise-semantics.test accept/interface-views.test accept/recursive-types.test stdlib/tree.test
  stdlib/collections.test stdlib/yaml-regressions.test accept/source-borrowed-wrapper-temporary-cleanup.test
  accept/faulting-close-releases-parts.test stdlib/http-exchange-helpers.test
  stdlib/http-close-drains stdlib/http-fault-handler-frees-exchange-view stdlib/promise-closes-captured-pipe
  stdlib/cancelled-file-read-frees-buffer stdlib/cancelled-dns-query-frees-state
  stdlib/cancelled-serve-start-frees-handler stdlib/cancelled-tls-handshake-frees-state)
add_test(NAME leak_check COMMAND ${CMAKE_COMMAND} -DMS_C=$<TARGET_FILE:ms> -DFIXTURES=${CMAKE_SOURCE_DIR}/tests/conformance/fixtures/e2e
  "-DNAMES=${MS_LEAK_FIXTURES}" -DWORK=${CMAKE_BINARY_DIR}/src/cli/leak -P ${CMAKE_SOURCE_DIR}/cmake/LeakCheck.cmake)

# Every bundled standard-library body checks: `ms check` and `ms lint` check only the bodies a program reaches.
file(WRITE ${CMAKE_BINARY_DIR}/src/cli/std-full/main.ms "fn main() Void {\n    return\n}\n")
add_test(NAME std_full COMMAND ms check ${CMAKE_BINARY_DIR}/src/cli/std-full/main.ms --std)

# `ms add`, `ms install` and `ms remove` against a local git repository.
add_test(NAME package_run COMMAND ${CMAKE_COMMAND} -DMS_C=$<TARGET_FILE:ms> -DWORK=${CMAKE_BINARY_DIR}/src/cli/package
  -P ${CMAKE_SOURCE_DIR}/cmake/PackageRun.cmake)

# The folded-stack conversion of `ms profile`, without the compiler.
ms_executable(profile_folded_unit cli SOURCES profile_folded_unit.c profile_folded.c LINK ms_base)
add_test(NAME driver_profile_folded COMMAND profile_folded_unit)

# `ms profile` end to end: a program that burns CPU is built, run under the sampler and turned into a bundle.
add_test(NAME profile_run COMMAND ${CMAKE_COMMAND} -DMS_C=$<TARGET_FILE:ms> -DWORK=${CMAKE_BINARY_DIR}/src/cli/profile
  -DTOOL_DIR=${MS_COMPILER_BIN} -P ${CMAKE_SOURCE_DIR}/cmake/ProfileRun.cmake)

# `ms bench` end to end: a real bench block is built and run, and the report's shape is checked.
add_test(NAME bench_run COMMAND ${CMAKE_COMMAND} -DMS_C=$<TARGET_FILE:ms> -DWORK=${CMAKE_BINARY_DIR}/src/cli/bench
  -DTOOL_DIR=${MS_COMPILER_BIN} -P ${CMAKE_SOURCE_DIR}/cmake/BenchRun.cmake)

# `ms search_symbol` over many files searches every one.
add_test(NAME search_many COMMAND ${CMAKE_COMMAND} -DMS_C=$<TARGET_FILE:ms> -DWORK=${CMAKE_BINARY_DIR}/src/cli/search-many
  -P ${CMAKE_SOURCE_DIR}/cmake/SearchMany.cmake)

# A command whose standard output cannot be written fails. Only Linux has /dev/full to write to.
if(EXISTS /dev/full)
  add_test(NAME stdout_full COMMAND ${CMAKE_COMMAND} -DMS_C=$<TARGET_FILE:ms> -P ${CMAKE_SOURCE_DIR}/cmake/StdoutFull.cmake)
endif()

# The same on every platform with a pipe whose reader closes: the child exits nonzero (a write error, or SIGPIPE).
add_test(NAME stdout_closed COMMAND ms run ${CMAKE_SOURCE_DIR}/tools/stdout-closed-check.ms WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
set_tests_properties(stdout_closed PROPERTIES ENVIRONMENT "MS=$<TARGET_FILE:ms>")

# Replays recorded language-server sessions (tests/lsp/<case>) over standard input and output.
file(GLOB MS_LSP_CASES LIST_DIRECTORIES true ${CMAKE_SOURCE_DIR}/tests/lsp/*)
foreach(case IN LISTS MS_LSP_CASES)
  if(IS_DIRECTORY ${case})
    get_filename_component(case_name ${case} NAME)
    add_test(NAME lsp_${case_name} COMMAND ${CMAKE_COMMAND} -DMS_C=$<TARGET_FILE:ms> -DCASE=${case}
      -DWORK=${CMAKE_BINARY_DIR}/src/cli/lsp-${case_name} -P ${CMAKE_SOURCE_DIR}/cmake/LspSession.cmake)
  endif()
endforeach()
