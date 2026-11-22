# Fills the startup-files directory (MS_FILES) next to ms-c; run after each build by MsRuntimePackage.cmake.
#   -DFILES=<dir> -DSOURCE_DIR=<repo> -DOS=<Linux|Darwin|Windows> -DARCH=<processor>
#   -DMUSL_DIR=<dir with crt1.o crti.o crtn.o libc.a libunwind.a> -DMINGW_DIR=<llvm-mingw root>
# Linux gets the glibc export table (and the musl and unwinder files for `--static` and the unwinder input);
# Windows gets the mingw-w64 startup object and libraries; macOS needs only the directory (the SDK stubs are
# made there on demand). A file that cannot be found is reported once and skipped.
cmake_minimum_required(VERSION 3.25)
file(MAKE_DIRECTORY "${FILES}")

if(ARCH MATCHES "^(aarch64|arm64|ARM64)$")
  set(arch aarch64)
else()
  set(arch x86_64)
endif()

function(ms_copy_file from name)
  if(EXISTS "${from}")
    file(COPY_FILE "${from}" "${FILES}/${name}" ONLY_IF_DIFFERENT)
  else()
    message(WARNING "startup files: ${name} not found at ${from}")
  endif()
endfunction()

if(OS STREQUAL "Linux")
  ms_copy_file("${SOURCE_DIR}/toolchain/glibc/${arch}.symbols" glibc.symbols)
  if(NOT MUSL_DIR)
    find_program(rustc rustc)
    if(rustc)
      execute_process(COMMAND "${rustc}" --print sysroot OUTPUT_VARIABLE sysroot OUTPUT_STRIP_TRAILING_WHITESPACE)
      set(MUSL_DIR "${sysroot}/lib/rustlib/${arch}-unknown-linux-musl/lib/self-contained")
    endif()
  endif()
  foreach(name crt1.o crti.o crtn.o libc.a libunwind.a)
    ms_copy_file("${MUSL_DIR}/${name}" ${name})
  endforeach()
elseif(OS STREQUAL "Windows")
  if(NOT MINGW_DIR)
    set(MINGW_DIR "${SOURCE_DIR}/target/llvm-bundle/mingw")
  endif()
  set(lib "${MINGW_DIR}/${arch}-w64-mingw32/lib")
  foreach(name crt2.o libmingw32.a libunwind.a libmoldname.a libmingwex.a libucrt.a libadvapi32.a libbcrypt.a
          libcrypt32.a libdbghelp.a libntdll.a libsecur32.a libshell32.a libuser32.a libuserenv.a libiphlpapi.a
          libpsapi.a libole32.a libws2_32.a libsynchronization.a libkernel32.a)
    ms_copy_file("${lib}/${name}" ${name})
  endforeach()
  file(GLOB builtins "${MINGW_DIR}/lib/clang/*/lib/windows/libclang_rt.builtins-${arch}.a")
  list(GET builtins 0 builtin)
  ms_copy_file("${builtin}" libclang_rt.builtins.a)
endif()
