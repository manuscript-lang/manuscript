# The bundled standard library is generated from stdlib/ at build time.
set(std_embedded ${CMAKE_CURRENT_BINARY_DIR}/std_embedded.c)
file(GLOB_RECURSE std_files CONFIGURE_DEPENDS ${PROJECT_SOURCE_DIR}/stdlib/*.ms)
add_custom_command(
  OUTPUT ${std_embedded}
  COMMAND ${CMAKE_COMMAND} -DSTDLIB_DIR=${PROJECT_SOURCE_DIR}/stdlib -DOUTPUT=${std_embedded}
          -P ${PROJECT_SOURCE_DIR}/cmake/EmbedStdlib.cmake
  DEPENDS ${std_files} ${PROJECT_SOURCE_DIR}/cmake/EmbedStdlib.cmake
  COMMENT "Embedding stdlib/*.ms")
add_library(ms_project STATIC discover.c embed.c files.c load.c manifest.c project.c resolve.c toml.c ${std_embedded})
ms_target_defaults(ms_project)
target_include_directories(ms_project PRIVATE ${PROJECT_SOURCE_DIR}/src)
target_link_libraries(ms_project PUBLIC ms_syntax ms_base)
