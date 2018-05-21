include(CMakeParseArguments)

# BuildLibuv(TARGET targetname CONFIGURE_COMMAND ... BUILD_COMMAND ... INSTALL_COMMAND ...)
# Reusable function to build libuv, wraps ExternalProject_Add.
# Failing to pass a command argument will result in no command being run
function(BuildLibuv)
  cmake_parse_arguments(_libuv
    "BUILD_IN_SOURCE"
    "TARGET"
    "PATCH_COMMAND;CONFIGURE_COMMAND;BUILD_COMMAND;INSTALL_COMMAND"
    ${ARGN})

  if(NOT _libuv_CONFIGURE_COMMAND AND NOT _libuv_BUILD_COMMAND
        AND NOT _libuv_INSTALL_COMMAND)
    message(FATAL_ERROR "Must pass at least one of CONFIGURE_COMMAND, BUILD_COMMAND, INSTALL_COMMAND")
  endif()
  if(NOT _libuv_TARGET)
    set(_libuv_TARGET "libuv")
  endif()

  ExternalProject_Add(${_libuv_TARGET}
    PREFIX ${DEPS_BUILD_DIR}
    URL ${LIBUV_URL}
    DOWNLOAD_DIR ${DEPS_DOWNLOAD_DIR}/libuv
    DOWNLOAD_COMMAND ${CMAKE_COMMAND}
      -DPREFIX=${DEPS_BUILD_DIR}
      -DDOWNLOAD_DIR=${DEPS_DOWNLOAD_DIR}/libuv
      -DURL=${LIBUV_URL}
      -DEXPECTED_SHA256=${LIBUV_SHA256}
      -DTARGET=${_libuv_TARGET}
      -DUSE_EXISTING_SRC_DIR=${USE_EXISTING_SRC_DIR}
      -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/DownloadAndExtractFile.cmake
    BUILD_IN_SOURCE ${_libuv_BUILD_IN_SOURCE}
    PATCH_COMMAND "${_libuv_PATCH_COMMAND}"
    CONFIGURE_COMMAND "${_libuv_CONFIGURE_COMMAND}"
    BUILD_COMMAND "${_libuv_BUILD_COMMAND}"
    INSTALL_COMMAND "${_libuv_INSTALL_COMMAND}")
endfunction()

set(UNIX_CFGCMD sh ${DEPS_BUILD_DIR}/src/libuv/autogen.sh &&
  ${DEPS_BUILD_DIR}/src/libuv/configure --with-pic --disable-shared
  --prefix=${DEPS_INSTALL_DIR} --libdir=${DEPS_INSTALL_DIR}/lib
  CC=${DEPS_C_COMPILER})

set(LIBUV_PATCH_COMMAND
${GIT_EXECUTABLE} -C ${DEPS_BUILD_DIR}/src/libuv init
  COMMAND ${GIT_EXECUTABLE} -C ${DEPS_BUILD_DIR}/src/libuv apply
    ${CMAKE_CURRENT_SOURCE_DIR}/patches/libuv-overlapped.patch)

if(UNIX)
  BuildLibuv(
    CONFIGURE_COMMAND ${UNIX_CFGCMD} MAKE=${MAKE_PRG}
    INSTALL_COMMAND ${MAKE_PRG} V=1 install)

elseif(MINGW AND CMAKE_CROSSCOMPILING)
  # Build libuv for the host
  BuildLibuv(TARGET libuv_host
    CONFIGURE_COMMAND sh ${DEPS_BUILD_DIR}/src/libuv_host/autogen.sh && ${DEPS_BUILD_DIR}/src/libuv_host/configure --with-pic --disable-shared --prefix=${HOSTDEPS_INSTALL_DIR} CC=${HOST_C_COMPILER}
    INSTALL_COMMAND ${MAKE_PRG} V=1 install)

  # Build libuv for the target
  BuildLibuv(
    PATCH_COMMAND ${LIBUV_PATCH_COMMAND}
    CONFIGURE_COMMAND ${UNIX_CFGCMD} --host=${CROSS_TARGET}
    INSTALL_COMMAND ${MAKE_PRG} V=1 install)

elseif((WIN32 AND MSVC) OR (MINGW AND CMAKE_GENERATOR MATCHES "Ninja"))

  set(UV_OUTPUT_DIR ${DEPS_BUILD_DIR}/src/libuv/${CMAKE_BUILD_TYPE})
  if(MSVC)
    set(INSTALL_CMD ${CMAKE_COMMAND} --build . --target install --config ${CMAKE_BUILD_TYPE}
      # Some applications (lua-client/luarocks) look for uv.lib instead of libuv.lib
      COMMAND ${CMAKE_COMMAND} -E copy ${UV_OUTPUT_DIR}/libuv.lib ${DEPS_INSTALL_DIR}/lib/uv.lib
      COMMAND ${CMAKE_COMMAND} -E copy ${UV_OUTPUT_DIR}/libuv.dll ${DEPS_INSTALL_DIR}/bin/
      COMMAND ${CMAKE_COMMAND} -E copy ${UV_OUTPUT_DIR}/libuv.dll ${DEPS_INSTALL_DIR}/bin/uv.dll
      COMMAND ${CMAKE_COMMAND} -E make_directory ${DEPS_INSTALL_DIR}/include
      COMMAND ${CMAKE_COMMAND} -E copy_directory ${DEPS_BUILD_DIR}/src/libuv/include ${DEPS_INSTALL_DIR}/include)
  else()
    set(INSTALL_CMD ${CMAKE_COMMAND} --build . --target install --config ${CMAKE_BUILD_TYPE})
  endif()
  BuildLibUv(BUILD_IN_SOURCE
    PATCH_COMMAND ${LIBUV_PATCH_COMMAND}
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E copy
        ${CMAKE_CURRENT_SOURCE_DIR}/cmake/LibuvCMakeLists.txt
        ${DEPS_BUILD_DIR}/src/libuv/CMakeLists.txt
      COMMAND ${CMAKE_COMMAND} ${DEPS_BUILD_DIR}/src/libuv/CMakeLists.txt
        -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
        -DCMAKE_GENERATOR=${CMAKE_GENERATOR}
        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
        -DBUILD_SHARED_LIBS=ON
        -DCMAKE_INSTALL_PREFIX=${DEPS_INSTALL_DIR}
    BUILD_COMMAND ${CMAKE_COMMAND} --build . --config ${CMAKE_BUILD_TYPE}
    INSTALL_COMMAND ${INSTALL_CMD})

elseif(MINGW)

  # Native MinGW
  BuildLibUv(BUILD_IN_SOURCE
    PATCH_COMMAND ${LIBUV_PATCH_COMMAND}
    BUILD_COMMAND ${CMAKE_MAKE_PROGRAM} -f Makefile.mingw
    INSTALL_COMMAND ${CMAKE_COMMAND} -E make_directory ${DEPS_INSTALL_DIR}/lib
      COMMAND ${CMAKE_COMMAND} -E copy ${DEPS_BUILD_DIR}/src/libuv/libuv.a ${DEPS_INSTALL_DIR}/lib
      COMMAND ${CMAKE_COMMAND} -E make_directory ${DEPS_INSTALL_DIR}/include
      COMMAND ${CMAKE_COMMAND} -E copy_directory ${DEPS_BUILD_DIR}/src/libuv/include ${DEPS_INSTALL_DIR}/include
    )

else()
  message(FATAL_ERROR "Trying to build libuv in an unsupported system ${CMAKE_SYSTEM_NAME}/${CMAKE_C_COMPILER_ID}")
endif()

list(APPEND THIRD_PARTY_DEPS libuv)
