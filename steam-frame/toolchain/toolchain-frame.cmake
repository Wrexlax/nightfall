# Cross toolchain for the Steam Frame (Linux arm64), Godot's buildroot SDK (GCC 13.2, glibc 2.28).
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(FRAME_SDK "$ENV{FRAME_SDK}")
set(CMAKE_SYSROOT "${FRAME_SDK}/aarch64-godot-linux-gnu/sysroot")
set(CMAKE_C_COMPILER "${FRAME_SDK}/bin/aarch64-godot-linux-gnu-gcc")
set(CMAKE_CXX_COMPILER "${FRAME_SDK}/bin/aarch64-godot-linux-gnu-g++")
set(CMAKE_AR "${FRAME_SDK}/bin/aarch64-godot-linux-gnu-ar" CACHE FILEPATH "")
set(CMAKE_RANLIB "${FRAME_SDK}/bin/aarch64-godot-linux-gnu-ranlib" CACHE FILEPATH "")
set(CMAKE_STRIP "${FRAME_SDK}/bin/aarch64-godot-linux-gnu-strip" CACHE FILEPATH "")
# The sysroot plus vcpkg's arm64 install tree; never the build machine's own /usr.
set(CMAKE_FIND_ROOT_PATH "${CMAKE_SYSROOT}" "$ENV{FRAME_NATIVE}/vcpkg_installed/arm64-linux")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
# Everything ends up inside one shared library (the GDExtension), so all of it,
# static dependencies included, must be position independent.
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
# The rest are the SDK's own default flags (its share/buildroot/toolchainfile.cmake),
# which build 4i and earlier were compiled with: large-file names, -O2, and
# _FORTIFY_SOURCE=1 (libc checks on common buffer functions).
set(FRAME_FLAGS "-fPIC -D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -D_FORTIFY_SOURCE=1")
set(CMAKE_C_FLAGS_INIT "${FRAME_FLAGS}")
set(CMAKE_CXX_FLAGS_INIT "${FRAME_FLAGS}")
set(CMAKE_C_FLAGS_RELEASE "-O2 -DNDEBUG" CACHE STRING "")
set(CMAKE_CXX_FLAGS_RELEASE "-O2 -DNDEBUG" CACHE STRING "")
