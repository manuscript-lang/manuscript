# The runtime: sys, core, io, net, std. Sources join ms_runtime as their layers land.
add_library(ms_runtime INTERFACE)
add_subdirectory(sys)
add_subdirectory(core)
target_link_libraries(ms_runtime INTERFACE ms_abi ms_sys ms_core ms_values)
