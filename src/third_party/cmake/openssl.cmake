# OpenSSL 3.5.4, static libssl and libcrypto, built out of tree with its own Configure (perl) so the vendored
# source is never written to. Libraries only: no apps, tests, docs, shared objects, engines or modules.
# Unix builds with make. Windows builds upstream's way: MSVC (vcvarsall), nmake, Strawberry Perl, and NASM on x64.
include(ExternalProject)
if(WIN32)
  # Git for Windows ships a perl without the modules Configure loads; use Strawberry Perl.
  find_program(MS_PERL perl HINTS C:/Strawberry/perl/bin NO_DEFAULT_PATH)
endif()
find_program(MS_PERL perl REQUIRED)
set(OPENSSL_DIR ${CMAKE_CURRENT_SOURCE_DIR}/openssl)
set(OPENSSL_BUILD ${CMAKE_CURRENT_BINARY_DIR}/openssl_build)
set(OPENSSL_CC ${CMAKE_C_COMPILER})
if(MS_CCACHE)
  set(OPENSSL_CC "${MS_CCACHE} ${CMAKE_C_COMPILER}")
endif()
set(OPENSSL_OPTIONS no-shared no-tests no-apps no-docs no-module no-engine no-dso no-legacy no-comp no-ssl3
  no-weak-ssl-ciphers no-autoload-config no-ui-console no-deprecated)
if(WIN32)
  if(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|arm64|aarch64")
    set(OPENSSL_TARGET VC-WIN64-ARM)
    set(OPENSSL_VCARCH arm64)
  else()
    set(OPENSSL_TARGET VC-WIN64A)
    set(OPENSSL_VCARCH x64)
  endif()
  set(OPENSSL_LIB_SUFFIX .lib)
  set(OPENSSL_LIB_PREFIX "")
  # Configure and nmake need the MSVC environment (cl, nmake); vcvarsall sets it up for one cmd session.
  find_program(MS_VSWHERE vswhere HINTS "$ENV{ProgramFiles\(x86\)}/Microsoft Visual Studio/Installer" REQUIRED)
  execute_process(COMMAND ${MS_VSWHERE} -latest -products * -property installationPath
    OUTPUT_VARIABLE MS_VS_PATH OUTPUT_STRIP_TRAILING_WHITESPACE)
  file(TO_NATIVE_PATH "${MS_VS_PATH}/VC/Auxiliary/Build/vcvarsall.bat" MS_VCVARSALL)
  file(TO_NATIVE_PATH "${MS_PERL}" MS_PERL_NATIVE)
  file(TO_NATIVE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/openssl/Configure" MS_CONFIGURE_NATIVE)
  string(REPLACE ";" " " MS_OPENSSL_ARGS "${OPENSSL_OPTIONS}")
  set(OPENSSL_SCRIPT ${CMAKE_CURRENT_BINARY_DIR}/openssl_build.cmd)
  file(WRITE ${OPENSSL_SCRIPT}
"@echo off
call \"${MS_VCVARSALL}\" ${OPENSSL_VCARCH} || exit /b 1
set \"PATH=%PATH%;C:\\Program Files\\NASM\"
if \"%1\"==\"configure\" \"${MS_PERL_NATIVE}\" \"${MS_CONFIGURE_NATIVE}\" ${OPENSSL_TARGET} ${MS_OPENSSL_ARGS}
if \"%1\"==\"build\" nmake build_libs
exit /b %ERRORLEVEL%
")
  set(OPENSSL_CONFIGURE_COMMAND cmd /C ${OPENSSL_SCRIPT} configure)
  set(OPENSSL_BUILD_COMMAND cmd /C ${OPENSSL_SCRIPT} build)
else()
  set(OPENSSL_BUILD_COMMAND make build_libs)
  set(OPENSSL_LIB_SUFFIX .a)
  set(OPENSSL_LIB_PREFIX lib)
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
  set(OPENSSL_CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CC=${OPENSSL_CC}
    ${MS_PERL} ${OPENSSL_DIR}/Configure ${OPENSSL_TARGET} ${OPENSSL_OPTIONS} -fPIC)
endif()
set(OPENSSL_CRYPTO ${OPENSSL_BUILD}/${OPENSSL_LIB_PREFIX}crypto${OPENSSL_LIB_SUFFIX})
set(OPENSSL_SSL ${OPENSSL_BUILD}/${OPENSSL_LIB_PREFIX}ssl${OPENSSL_LIB_SUFFIX})
file(MAKE_DIRECTORY ${OPENSSL_BUILD}/include)
ExternalProject_Add(openssl_build
  SOURCE_DIR ${OPENSSL_DIR}
  BINARY_DIR ${OPENSSL_BUILD}
  CONFIGURE_COMMAND ${OPENSSL_CONFIGURE_COMMAND}
  BUILD_COMMAND ${OPENSSL_BUILD_COMMAND}
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
