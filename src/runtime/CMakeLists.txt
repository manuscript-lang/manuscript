# The runtime: sys, core, io, net, std. Sources join ms_runtime as their layers land.
add_library(ms_runtime INTERFACE)
add_subdirectory(sys)
add_subdirectory(io)
add_subdirectory(core)
add_subdirectory(entry)
add_subdirectory(std)
target_link_libraries(ms_runtime INTERFACE ms_abi ms_sys ms_io ms_core ms_entry ms_values ms_std_text ms_std_data ms_std_time ms_std_math ms_std_random ms_std_compress ms_std_crypto ms_std_path ms_std_bignum ms_std_system ms_std_process ms_std_fs)
