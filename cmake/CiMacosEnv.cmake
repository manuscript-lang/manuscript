# The setting the macOS jobs need before they build: TMPDIR as the real path of the runner's temp directory
# (/var is a symlink to /private/var, so a fixture that prints its work directory would differ). Run as `cmake -P cmake/CiMacosEnv.cmake`.
get_filename_component(real_temp "$ENV{RUNNER_TEMP}" REALPATH)
file(APPEND "$ENV{GITHUB_ENV}" "TMPDIR=${real_temp}\n")
