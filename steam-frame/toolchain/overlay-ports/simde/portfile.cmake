# header-only library

vcpkg_from_git(
    OUT_SOURCE_PATH SOURCE_PATH
    URL "https://github.com/simd-everywhere/simde"
    REF 71fd833d9666141edcd1d3c109a80e228303d8d7
    FETCH_REF "v0.8.2"
    HEAD_REF master
)

file(COPY "${SOURCE_PATH}/simde" DESTINATION "${CURRENT_PACKAGES_DIR}/include")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
