# The app's QML plugin: tags, covers, playlist files and folders (see the
# headers).
add_library(musicapp-qml MODULE
    plugin.cpp plugin.h
    tags.cpp tags.h
    artwork.cpp artwork.h
    artprovider.cpp artprovider.h
    tagcache.cpp tagcache.h
    playlistfiles.cpp playlistfiles.h
    filebrowser.cpp filebrowser.h
)

# So the plugin can be found next to its qmldir when running from the build tree.
file(COPY qmldir DESTINATION ${CMAKE_CURRENT_BINARY_DIR})

target_link_libraries(musicapp-qml PRIVATE Qt6::Qml Qt6::Quick Qt6::Gui PkgConfig::TAGLIB)

install(TARGETS musicapp-qml DESTINATION ${PLUGIN_DIR})
install(FILES qmldir DESTINATION ${PLUGIN_DIR})
