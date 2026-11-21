# OpenSSL 3.5.4, static libssl and libcrypto, built out of tree with its own Configure (perl) so the vendored
# source is never written to. Libraries only: no apps, tests, docs, shared objects, engines or modules.
# Everything builds with make. Windows is the mingw-w64 ABI (what ms links programs with): MSYS2 clang, with its own perl
# and make as a pair (Git's perl lacks modules Configure loads, and records paths only MSYS2 make resolves).
include(ExternalProject)
find_program(MS_PERL perl REQUIRED)
set(OPENSSL_DIR ${CMAKE_CURRENT_SOURCE_DIR}/openssl)
set(OPENSSL_BUILD ${CMAKE_CURRENT_BINARY_DIR}/openssl_build)
set(OPENSSL_OPTIONS no-shared no-tests no-apps no-docs no-module no-engine no-dso no-legacy no-comp no-ssl3
  no-weak-ssl-ciphers no-autoload-config no-ui-console no-deprecated)
set(OPENSSL_MAKE make)
set(OPENSSL_LIB_SUFFIX .a)
set(OPENSSL_LIB_PREFIX lib)
set(OPENSSL_TOOLS)
if(WIN32)
  set(OPENSSL_TARGET mingw64)
  set(OPENSSL_TOOLS AR=llvm-ar RANLIB=llvm-ranlib RC=llvm-windres)
  if(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|arm64|aarch64")
    list(APPEND OPENSSL_OPTIONS no-asm)
  endif()
else()
  if(APPLE)
    set(OPENSSL_TARGET darwin64-${CMAKE_SYSTEM_PROCESSOR}-cc)
    if(CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64")
      set(OPENSSL_TARGET darwin64-arm64-cc)
    endif()
  elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
    set(OPENSSL_TARGET linux-aarch64)
  else()
    set(OPENSSL_TARGET linux-x86_64)
  endif()
endif()
set(OPENSSL_CC ${CMAKE_C_COMPILER})
if(MS_CCACHE)
  set(OPENSSL_CC "${MS_CCACHE} ${CMAKE_C_COMPILER}")
endif()
set(OPENSSL_CRYPTO ${OPENSSL_BUILD}/${OPENSSL_LIB_PREFIX}crypto${OPENSSL_LIB_SUFFIX})
set(OPENSSL_SSL ${OPENSSL_BUILD}/${OPENSSL_LIB_PREFIX}ssl${OPENSSL_LIB_SUFFIX})
file(MAKE_DIRECTORY ${OPENSSL_BUILD}/include)
ExternalProject_Add(openssl_build
  SOURCE_DIR ${OPENSSL_DIR}
  BINARY_DIR ${OPENSSL_BUILD}
  CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CC=${OPENSSL_CC} ${OPENSSL_TOOLS}
    ${MS_PERL} ${OPENSSL_DIR}/Configure ${OPENSSL_TARGET} ${OPENSSL_OPTIONS} -fPIC
  BUILD_COMMAND ${OPENSSL_MAKE} build_libs
  INSTALL_COMMAND ""
  BUILD_BYPRODUCTS ${OPENSSL_CRYPTO} ${OPENSSL_SSL}
  USES_TERMINAL_BUILD OFF)

add_library(openssl_crypto STATIC IMPORTED GLOBAL)
set_target_properties(openssl_crypto PROPERTIES IMPORTED_LOCATION ${OPENSSL_CRYPTO}
  INTERFACE_INCLUDE_DIRECTORIES "${OPENSSL_DIR}/include;${OPENSSL_BUILD}/include")
add_library(openssl_ssl STATIC IMPORTED GLOBAL)
set_target_properties(openssl_ssl PROPERTIES IMPORTED_LOCATION ${OPENSSL_SSL}
  INTERFACE_INCLUDE_DIRECTORIES "${OPENSSL_DIR}/include;${OPENSSL_BUILD}/include")
add_dependencies(openssl_crypto openssl_build)
add_dependencies(openssl_ssl openssl_build)
target_link_libraries(openssl_ssl INTERFACE openssl_crypto)
if(WIN32)
  target_link_libraries(openssl_crypto INTERFACE ws2_32 crypt32 advapi32 user32)
else()
  target_link_libraries(openssl_crypto INTERFACE Threads::Threads ${CMAKE_DL_LIBS})
endif()
