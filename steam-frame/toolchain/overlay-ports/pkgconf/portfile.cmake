# Placeholder: use the build machine's own pkg-config instead of building pkgconf
# (its source archive isn't reachable from this workspace).
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)
file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/tools/pkgconf")
file(WRITE "${CURRENT_PACKAGES_DIR}/tools/pkgconf/pkgconf" "#!/bin/sh\nexec /usr/bin/pkg-config \"$@\"\n")
file(CHMOD "${CURRENT_PACKAGES_DIR}/tools/pkgconf/pkgconf" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
file(WRITE "${CURRENT_PACKAGES_DIR}/share/pkgconf/copyright" "System pkg-config is used; nothing is redistributed.\n")
