add_executable(ms-c pipeline.c backend.c emit_command.c main.c phases.c check_command.c fmt_command.c check_fix.c check_inputs.c display.c fmt_targets.c fmt_labels.c init_command.c watch.c package_cache.c package_commands.c package_fetch.c package_git.c package_validate.c snippet.c)
ms_target_defaults(ms-c)
target_link_libraries(ms-c PRIVATE ms_base ms_syntax ms_project ms_check ms_own ms_lower ms_mir ms_opt ms_emit ms_link)

set(MS_MUSL_DIR "" CACHE PATH "Directory with crt1.o crti.o crtn.o libc.a libunwind.a (default: rustc's musl sysroot)")
set(MS_MINGW_DIR "" CACHE PATH "llvm-mingw root for Windows links (default: target/llvm-bundle/mingw)")
include(MsRuntimePackage)
ms_package_runtime(ms-c ms_runtime)
