# The two settings the macOS jobs need before they build: TMPDIR as the real path of the runner's temp directory
# (/var is a symlink to /private/var, so a fixture that prints its work directory would differ), and Homebrew's
# keg-only llvm on PATH (release builds run its opt and llc). Run as `cmake -P cmake/CiMacosEnv.cmake`.
get_filename_component(real_temp "$ENV{RUNNER_TEMP}" REALPATH)
file(APPEND "$ENV{GITHUB_ENV}" "TMPDIR=${real_temp}\n")
execute_process(COMMAND brew --prefix llvm OUTPUT_VARIABLE llvm_prefix OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
file(APPEND "$ENV{GITHUB_PATH}" "${llvm_prefix}/bin\n")
