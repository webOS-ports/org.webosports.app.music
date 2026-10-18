cmake_minimum_required(VERSION 3.16)
project(org.webosports.app.music CXX)

set(CMAKE_INCLUDE_CURRENT_DIR ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(APP_ID org.webosports.app.music)
set(APP_DIR ${CMAKE_CURRENT_BINARY_DIR}/${APP_ID})

# The webOS CMake modules on LuneOS; without them (a desktop build for the
# tests) the app goes under the build tree.
include(webOS/webOS OPTIONAL RESULT_VARIABLE FOUND_WEBOS_MODULE_PATH)
if(NOT "${FOUND_WEBOS_MODULE_PATH}" STREQUAL "NOTFOUND")
    webos_modules_init(1 0 0 QUALIFIER RC3)
    webos_component(1 0 0)
    if(NOT "${WEBOS_INSTALL_ROOT}" STREQUAL "/usr/local/webos")
        set(APP_DIR ${WEBOS_INSTALL_WEBOS_APPLICATIONSDIR}/${APP_ID})
    endif()
endif()

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fvisibility=hidden -fvisibility-inlines-hidden -Wall -Wextra")

include(GNUInstallDirs)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick)
find_package(PkgConfig REQUIRED)
pkg_check_modules(TAGLIB REQUIRED IMPORTED_TARGET taglib>=2.0)

set(PLUGIN_DIR ${APP_DIR}/MusicApp)
message(STATUS "APP_DIR=${APP_DIR}")

install(FILES appinfo.json icon.png icon-256x256.png DESTINATION ${APP_DIR})

