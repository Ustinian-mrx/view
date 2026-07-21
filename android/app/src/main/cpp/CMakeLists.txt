cmake_minimum_required(VERSION 3.22.1)
project(vision_ncnn)

add_library(vision_ncnn SHARED ncnn_jni.cpp)

find_library(log-lib log)
find_library(android-lib android)

set(NCNN_SO ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libncnn.so)
set(NCNN_INCLUDE ${CMAKE_SOURCE_DIR}/ncnn/include)

if(EXISTS ${NCNN_SO} AND EXISTS ${NCNN_INCLUDE}/ncnn/net.h)
    add_library(ncnn SHARED IMPORTED)
    set_target_properties(ncnn PROPERTIES IMPORTED_LOCATION ${NCNN_SO})
    target_include_directories(vision_ncnn PRIVATE ${NCNN_INCLUDE})
    target_compile_definitions(vision_ncnn PRIVATE VISION_GUARD_WITH_NCNN=1)
    target_link_libraries(vision_ncnn ncnn ${log-lib} ${android-lib})
else()
    message(WARNING "NCNN runtime not found. Building vision_ncnn with heuristic fallback only.")
    target_compile_definitions(vision_ncnn PRIVATE VISION_GUARD_WITH_NCNN=0)
    target_link_libraries(vision_ncnn ${log-lib} ${android-lib})
endif()
