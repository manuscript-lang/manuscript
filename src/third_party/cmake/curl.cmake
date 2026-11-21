# curl 8.23.0 (libcurl only), static. HTTP and HTTP/2 (nghttp2) with zlib and a threaded resolver; TLS through
# OpenSSL on Unix (Windows has no TLS backend yet). The configuration header comes from curl's own template,
# filled in with the results of the checks below. Windows uses curl's config-win32.h and needs no generated header.
set(CURL_DIR ${CMAKE_CURRENT_SOURCE_DIR}/curl)
set(CURL_GEN ${CMAKE_CURRENT_BINARY_DIR}/curl_gen)

file(READ ${CURL_DIR}/lib/Makefile.inc CURL_INC)
string(REGEX MATCHALL "\n[ ]+[A-Za-z0-9_/-]+\\.c" CURL_INC_LINES "${CURL_INC}")
set(CURL_SOURCES)
foreach(line IN LISTS CURL_INC_LINES)
  string(STRIP "${line}" source)
  list(APPEND CURL_SOURCES ${CURL_DIR}/lib/${source})
endforeach()

add_library(curl STATIC ${CURL_SOURCES})
target_include_directories(curl ${MS_THIRD_PARTY_SYSTEM} PUBLIC ${CURL_DIR}/include PRIVATE ${CURL_DIR}/lib ${CURL_GEN})
target_compile_definitions(curl PUBLIC CURL_STATICLIB PRIVATE BUILDING_LIBCURL USE_NGHTTP2 HAVE_LIBZ)
target_link_libraries(curl PUBLIC zlib nghttp2)

if(WIN32)
  # curl's config-win32.h is for MSVC only; mingw-w64 gets the same settings from this generated header.
  file(MAKE_DIRECTORY ${CURL_GEN})
  file(GENERATE OUTPUT ${CURL_GEN}/curl_config.h CONTENT [=[
#define HAVE_FCNTL_H 1
#define HAVE_IO_H 1
#define HAVE_LOCALE_H 1
#define HAVE_STDBOOL_H 1
#define HAVE_BOOL_T 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_UTIME_H 1
#define HAVE_CLOSESOCKET 1
#define HAVE_FREEADDRINFO 1
#define HAVE_GETADDRINFO 1
#define HAVE_GETADDRINFO_THREADSAFE 1
#define HAVE_GETHOSTNAME 1
#define HAVE_GETPEERNAME 1
#define HAVE_GETSOCKNAME 1
#define HAVE_IOCTLSOCKET 1
#define HAVE_IOCTLSOCKET_FIONBIO 1
#define HAVE_SETLOCALE 1
#define HAVE_SOCKET 1
#define HAVE_UTIME 1
#define HAVE_RECV 1
#define RECV_TYPE_ARG1 SOCKET
#define RECV_TYPE_ARG2 char *
#define RECV_TYPE_ARG3 int
#define RECV_TYPE_ARG4 int
#define RECV_TYPE_RETV int
#define HAVE_SEND 1
#define SEND_TYPE_ARG1 SOCKET
#define SEND_TYPE_ARG2 char *
#define SEND_TYPE_ARG3 int
#define SEND_TYPE_ARG4 int
#define SEND_TYPE_RETV int
#define HAVE_SIGNAL 1
#define SIZEOF_INT 4
#define SIZEOF_LONG 4
#define SIZEOF_SIZE_T 8
#define SIZEOF_CURL_OFF_T 8
#define SIZEOF_TIME_T 8
#define SIZEOF_OFF_T 4
#define HAVE_STRUCT_SOCKADDR_STORAGE 1
#define HAVE_STRUCT_TIMEVAL 1
#define HAVE_SOCKADDR_IN6_SIN6_SCOPE_ID 1
#define USE_RESOLV_THREADED 1
#define USE_WIN32_CRYPTO 1
#define USE_UNIX_SOCKETS 1
#define CURL_OS "mingw-w64"
]=])
  target_compile_definitions(curl PRIVATE HAVE_CONFIG_H WIN32_LEAN_AND_MEAN USE_THREADS_WIN32)
  target_link_libraries(curl PUBLIC ws2_32 advapi32 crypt32 bcrypt iphlpapi)
else()
  include(CheckIncludeFile)
  include(CheckSymbolExists)
  include(CheckTypeSize)
  set(CURL_HEADERS arpa/inet.h fcntl.h ifaddrs.h libgen.h locale.h netdb.h netinet/in.h netinet/tcp.h
    netinet/udp.h poll.h pwd.h stdbool.h stdatomic.h strings.h sys/ioctl.h sys/param.h sys/poll.h
    sys/resource.h sys/select.h sys/types.h sys/un.h termios.h unistd.h utime.h dirent.h sys/filio.h
    sys/sockio.h linux/tcp.h sys/eventfd.h
    fnmatch.h sched.h signal.h sys/socket.h sys/stat.h sys/time.h sys/uio.h stdlib.h string.h time.h)
  # The headers the function checks include, in this order, when the platform has them (a missing one would fail every
  # check). net/if.h needs sys/socket.h first.
  set(CURL_SYMBOL_HEADERS sys/types.h sys/socket.h sys/stat.h sys/time.h sys/uio.h sys/un.h sys/ioctl.h unistd.h fcntl.h
    fnmatch.h libgen.h locale.h netdb.h net/if.h poll.h pwd.h sched.h signal.h stdlib.h string.h strings.h time.h utime.h
    dirent.h ifaddrs.h sys/eventfd.h sys/resource.h)
  set(CURL_FOUND_HEADERS)
  include(CheckIncludeFiles)
  check_include_files("sys/types.h;sys/socket.h;net/if.h" HAVE_NET_IF_H)
  foreach(header IN LISTS CURL_HEADERS)
    string(TOUPPER "HAVE_${header}" var)
    string(REGEX REPLACE "[/.]" "_" var "${var}")
    check_include_file(${header} ${var})
  endforeach()
  foreach(header IN LISTS CURL_SYMBOL_HEADERS)
    string(TOUPPER "HAVE_${header}" var)
    string(REGEX REPLACE "[/.]" "_" var "${var}")
    if(${var})
      list(APPEND CURL_FOUND_HEADERS ${header})
    endif()
  endforeach()
  set(CMAKE_REQUIRED_DEFINITIONS -D_GNU_SOURCE)
  set(CURL_FUNCTIONS accept4 alarm arc4random basename closesocket fchmod fcntl fnmatch freeaddrinfo fseeko
    getaddrinfo geteuid getppid gethostname getifaddrs getpeername getpwuid getpwuid_r getrlimit
    getsockname gettimeofday gmtime_r if_nametoindex localtime_r memrchr opendir pipe pipe2 poll realpath
    recv sched_yield send sendmsg sendmmsg setlocale setrlimit sigaction siginterrupt signal sigsetjmp
    socket socketpair strcasecmp strerror_r utime utimes eventfd memset_s)
  foreach(function IN LISTS CURL_FUNCTIONS)
    string(TOUPPER "HAVE_${function}" var)
    check_symbol_exists(${function} "${CURL_FOUND_HEADERS}" ${var})
  endforeach()
  unset(CMAKE_REQUIRED_DEFINITIONS)
  check_symbol_exists(CLOCK_MONOTONIC "time.h" HAVE_CLOCK_GETTIME_MONOTONIC)
  check_symbol_exists(O_NONBLOCK "fcntl.h" HAVE_FCNTL_O_NONBLOCK)
  check_symbol_exists(FIONBIO "sys/ioctl.h" HAVE_IOCTL_FIONBIO)
  check_symbol_exists(__GLIBC__ "features.h" HAVE_GLIBC_STRERROR_R)
  if(HAVE_GLIBC_STRERROR_R AND NOT APPLE)
    set(HAVE_POSIX_STRERROR_R)
  else()
    set(HAVE_POSIX_STRERROR_R 1)
    set(HAVE_GLIBC_STRERROR_R)
  endif()
  if(APPLE)
    check_symbol_exists(mach_absolute_time "mach/mach_time.h" HAVE_MACH_ABSOLUTE_TIME)
  endif()
  set(HAVE_BOOL_T ${HAVE_STDBOOL_H})
  set(HAVE_THREADS_POSIX 1)
  set(HAVE_STRUCT_TIMEVAL 1)
  set(HAVE_STRUCT_SOCKADDR_STORAGE 1)
  set(HAVE_SA_FAMILY_T 1)
  set(HAVE_SOCKADDR_IN6_SIN6_SCOPE_ID 1)
  set(HAVE_LIBZ 1)
  set(USE_IPV6 1)
  set(USE_UNIX_SOCKETS 1)
  set(USE_RESOLV_THREADED 1)
  set(USE_NGHTTP2 1)
  set(USE_OPENSSL 1)
  set(HAVE_SSL_SET0_WBIO 1)
  foreach(name DICT FILE FTP GOPHER IMAP LDAP LDAPS MQTT POP3 RTSP SMTP TELNET TFTP SMB)
    set(CURL_DISABLE_${name} 1)
  endforeach()
  foreach(type int long off_t size_t time_t)
    string(TOUPPER "${type}" upper)
    check_type_size(${type} SIZEOF_${upper})
    set(SIZEOF_${upper}_CODE "#define SIZEOF_${upper} ${SIZEOF_${upper}}")
  endforeach()
  set(SIZEOF_CURL_OFF_T_CODE "#define SIZEOF_CURL_OFF_T 8")
  set(SIZEOF_CURL_SOCKET_T_CODE "#define SIZEOF_CURL_SOCKET_T 4")
  string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}-${CMAKE_SYSTEM_NAME}" CURL_OS_NAME)
  set(CURL_OS "\"${CURL_OS_NAME}\"")
  configure_file(${CURL_DIR}/lib/curl_config-cmake.h.in ${CURL_GEN}/curl_config.h)
  target_compile_definitions(curl PRIVATE HAVE_CONFIG_H)
  if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    target_compile_definitions(curl PRIVATE _GNU_SOURCE)
  endif()
  target_link_libraries(curl PUBLIC openssl_ssl Threads::Threads)
  add_dependencies(curl openssl_build)
endif()
