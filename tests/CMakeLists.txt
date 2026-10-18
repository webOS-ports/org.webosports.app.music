# Unit tests for the app's C++: tags, covers, the tag cache, playlist files,
# folders and the state file. See README.md.
#
# Off by default, so image builds are unaffected:
#   cmake -DBUILD_TESTING=ON ...
# It needs googletest in the sysroot.

find_package(GTest REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Test)

add_executable(musicapp-tests
    unit/main.cpp
    unit/test_tags.cpp
    unit/test_artwork.cpp
    unit/test_tagcache.cpp
    unit/test_playlistfiles.cpp
    unit/test_filebrowser.cpp
    ${PROJECT_SOURCE_DIR}/MusicApp/tags.cpp
    ${PROJECT_SOURCE_DIR}/MusicApp/artwork.cpp
    ${PROJECT_SOURCE_DIR}/MusicApp/tagcache.cpp
    ${PROJECT_SOURCE_DIR}/MusicApp/tagcache.h
    ${PROJECT_SOURCE_DIR}/MusicApp/playlistfiles.cpp
    ${PROJECT_SOURCE_DIR}/MusicApp/playlistfiles.h
    ${PROJECT_SOURCE_DIR}/MusicApp/filebrowser.cpp
    ${PROJECT_SOURCE_DIR}/MusicApp/filebrowser.h
)
target_include_directories(musicapp-tests PRIVATE ${PROJECT_SOURCE_DIR}/MusicApp)
target_compile_definitions(musicapp-tests PRIVATE FIXTURES_DIR="${PROJECT_SOURCE_DIR}/tests/fixtures/music")
target_link_libraries(musicapp-tests PRIVATE GTest::gtest Qt6::Core Qt6::Gui Qt6::Test PkgConfig::TAGLIB)

add_test(NAME musicapp-unit COMMAND musicapp-tests)

# Device-sized screenshots of every screen (tools/screenshots-host.sh).
find_package(Qt6 REQUIRED COMPONENTS Gui Qml Quick)
add_executable(musicapp-screens screens/main.cpp)
target_link_libraries(musicapp-screens PRIVATE Qt6::Gui Qt6::Qml Qt6::Quick)
