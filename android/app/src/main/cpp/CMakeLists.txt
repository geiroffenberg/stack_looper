cmake_minimum_required(VERSION 3.22.1)

project(stack_looper_engine)

# Pull Oboe in via prefab (supplied by the Maven dep in build.gradle.kts).
find_package(oboe REQUIRED CONFIG)

add_library(stack_looper_engine SHARED
    engine.cpp
    jni_bridge.cpp
)

target_include_directories(stack_looper_engine PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(stack_looper_engine
    PRIVATE
    oboe::oboe
    android
    log
)
