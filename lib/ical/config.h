#ifndef LIBICAL_PORTABLE_CONFIG_H
#define LIBICAL_PORTABLE_CONFIG_H

#define PACKAGE_BUGREPORT "https://libical.github.io/libical/"
#define PACKAGE_NAME "libical"
#define PACKAGE_STRING "libical 3.0"
#define PACKAGE_TARNAME "libical"
#define PACKAGE_VERSION "3.0"

#define ICAL_ERRORS_ARE_FATAL 0
#define ICAL_ALLOW_EMPTY_PROPERTIES 1

#define HAVE_GMTIME_R 1
#define HAVE_LOCALTIME_R 1
#define HAVE_INTTYPES_H 1
#define HAVE_ISWSPACE 1
#define HAVE_STDBOOL_H 1
#define HAVE_WCTYPE_H 1
#define HAVE_SNPRINTF 1
#define HAVE_STAT 1
#define HAVE_FSTAT 1
#define HAVE_STRCASECMP 1
#define HAVE_STRNCASECMP 1
#define HAVE_STRDUP 1
#define HAVE_UNISTD_H 1
#define HAVE_FCNTL_H 1
#define HAVE_DIRENT_H 1
#define HAVE_USLEEP 1
#define HAVE_SETENV 1
#define HAVE_UNSETENV 1
#define HAVE_SIZEOF_INTPTR_T 1
#define HAVE_SIZEOF_SIZE_T 1
#define HAVE_SIZEOF_SSIZE_T 1
#define HAVE_SIZEOF_PID_T 1
#define SIZEOF_TIME_T 8

#if !defined(__wasi__)
#define HAVE_PTHREAD_H 1
#define HAVE_PTHREAD 1
#define HAVE_UNLINK 1
#endif

#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <wctype.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <limits.h>

#if !defined(MAXPATHLEN)
#define MAXPATHLEN PATH_MAX
#endif

#if !defined(bswap_32)
#define bswap_32 __builtin_bswap32
#endif
#if !defined(bswap_64)
#define bswap_64 __builtin_bswap64
#endif

#if !defined(MIN)
#define MIN(a, b) (((a) < (b)) ? (a) : (b))
#endif

#if !defined(_unused)
#define _unused(x) (void)x
#endif

#endif
