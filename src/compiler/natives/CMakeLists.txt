# The runtime natives' parameter lists, generated from the ms-sig comments of src/runtime.
set(native_sigs ${CMAKE_CURRENT_BINARY_DIR}/native_sigs.c)
file(GLOB_RECURSE runtime_headers CONFIGURE_DEPENDS ${PROJECT_SOURCE_DIR}/src/runtime/*.h)
add_custom_command(
  OUTPUT ${native_sigs}
  COMMAND ${CMAKE_COMMAND} -DSRC_DIR=${PROJECT_SOURCE_DIR}/src/runtime -DOUTPUT=${native_sigs}
          -P ${PROJECT_SOURCE_DIR}/cmake/EmbedNativeSigs.cmake
  DEPENDS ${runtime_headers} ${PROJECT_SOURCE_DIR}/cmake/EmbedNativeSigs.cmake
  COMMENT "Generating native signatures")
# The signature table is read by lowering and by the ownership pass (which natives borrow their result).
add_library(ms_native_sigs STATIC native_sig.c ${native_sigs})
ms_target_defaults(ms_native_sigs)
target_link_libraries(ms_native_sigs PUBLIC ms_base)
