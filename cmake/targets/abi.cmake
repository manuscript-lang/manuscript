add_library(ms_abi INTERFACE)
target_link_libraries(ms_abi INTERFACE ms_base)
target_include_directories(ms_abi INTERFACE "${CMAKE_SOURCE_DIR}/src")
