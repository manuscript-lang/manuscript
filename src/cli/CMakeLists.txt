add_executable(ms-c pipeline.c backend.c emit_command.c diagram_command.c review_command.c search_symbol_command.c search_project.c fault_record.c inspect_command.c main.c phases.c check_command.c verify_command.c json_value.c fmt_command.c check_fix.c checked_input.c findings.c check_selection.c display.c fmt_targets.c fmt_labels.c init_command.c invocation.c invocation_rules.c build_type.c build_command.c run_command.c test_command.c test_document.c bench_command.c profile_command.c profile_folded.c test_options.c test_records.c test_run.c watch.c package_cache.c package_commands.c package_fetch.c package_git.c package_validate.c snippet.c help_command.c help_text.c explain_command.c)
ms_target_defaults(ms-c)
file(STRINGS ${CMAKE_SOURCE_DIR}/.msversion MS_VERSION_TEXT LIMIT_COUNT 1)
target_compile_definitions(ms-c PRIVATE MS_VERSION="${MS_VERSION_TEXT}")
target_link_libraries(ms-c PRIVATE ms_base ms_syntax ms_project ms_check ms_own ms_lower ms_mir ms_opt ms_emit ms_link ms_tooling ms_std_text)

set(MS_MINGW_DIR "" CACHE PATH "llvm-mingw root for Windows links (default: target/llvm-bundle/mingw)")
include(MsRuntimePackage)
ms_add_musl_runtime()
ms_package_runtime(ms-c ms_runtime)

# Build and run a one-line program: packaging, pipeline and linker together on this platform.
get_filename_component(MS_COMPILER_BIN "${CMAKE_C_COMPILER}" DIRECTORY)
add_test(NAME smoke_run COMMAND ${CMAKE_COMMAND} -DMS_C=$<TARGET_FILE:ms-c> -DWORK=${CMAKE_CURRENT_BINARY_DIR}/smoke
  -DTOOL_DIR=${MS_COMPILER_BIN} -P ${CMAKE_SOURCE_DIR}/cmake/SmokeRun.cmake)

# The folded-stack conversion of `ms profile`, without the compiler.
add_executable(profile_folded_unit profile_folded_unit.c profile_folded.c)
ms_target_defaults(profile_folded_unit)
target_link_libraries(profile_folded_unit PRIVATE ms_base)
add_test(NAME driver_profile_folded COMMAND profile_folded_unit)

# `ms profile` end to end: a program that burns CPU is built, run under the sampler and turned into a bundle.
add_test(NAME profile_run COMMAND ${CMAKE_COMMAND} -DMS_C=$<TARGET_FILE:ms-c> -DWORK=${CMAKE_CURRENT_BINARY_DIR}/profile
  -DTOOL_DIR=${MS_COMPILER_BIN} -P ${CMAKE_SOURCE_DIR}/cmake/ProfileRun.cmake)

# `ms bench` end to end: a real bench block is built and run, and the report's shape is checked.
add_test(NAME bench_run COMMAND ${CMAKE_COMMAND} -DMS_C=$<TARGET_FILE:ms-c> -DWORK=${CMAKE_CURRENT_BINARY_DIR}/bench
  -DTOOL_DIR=${MS_COMPILER_BIN} -P ${CMAKE_SOURCE_DIR}/cmake/BenchRun.cmake)
