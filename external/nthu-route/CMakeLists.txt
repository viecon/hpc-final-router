cmake_minimum_required(VERSION 3.14)
project(NthuRoute VERSION 3.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Find Boost (header-only usage)
find_package(Boost REQUIRED)

# Find zlib (required for gzip file handling)
find_package(ZLIB REQUIRED)

option(NTHU_ROUTE_ENABLE_OPENMP "Enable OpenMP parallel analysis kernels" ON)
if(NTHU_ROUTE_ENABLE_OPENMP)
    find_package(OpenMP QUIET)
endif()

option(NTHU_ROUTE_ENABLE_CUDA "Enable CUDA dogleg preselection helper" OFF)
if(NTHU_ROUTE_ENABLE_CUDA)
    include(CheckLanguage)
    check_language(CUDA)
    if(CMAKE_CUDA_COMPILER)
        enable_language(CUDA)
        set(NTHU_ROUTE_CUDA_DOGLEG ON)
    else()
        message(WARNING "NTHU_ROUTE_ENABLE_CUDA=ON but no CUDA compiler was found; using CPU stub")
    endif()
endif()

# Project sources
set(PROJECT_SOURCES
    src/flute/flute.cpp
    src/grdb/RoutingComponent.cpp
    src/grdb/RoutingRegion.cpp
    src/grdb/parser.cpp
    src/misc/filehandler.cpp
    src/router/Congestion.cpp
    src/router/Construct_2d_tree.cpp
    src/router/DataDef.cpp
    src/router/Layerassignment.cpp
    src/router/MM_mazeroute.cpp
    src/router/Main.cpp
    src/router/MonotonicRouting.cpp
    src/router/OutputGeneration.cpp
    src/router/Post_processing.cpp
    src/router/Range_router.cpp
    src/router/Route.cpp
    src/router/Route_2pinnets.cpp
    src/router/flute4nthuroute.cpp
    src/router/parameter.cpp
)

if(NTHU_ROUTE_CUDA_DOGLEG)
    list(APPEND PROJECT_SOURCES src/router/CudaDogleg.cu)
else()
    list(APPEND PROJECT_SOURCES src/router/CudaDogleg_stub.cpp)
endif()

add_executable(NthuRoute ${PROJECT_SOURCES})

target_include_directories(NthuRoute PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${Boost_INCLUDE_DIRS}
)

# Treat spdlog headers as system headers to suppress warnings
target_include_directories(NthuRoute SYSTEM PRIVATE
    ${CMAKE_SOURCE_DIR}/src/spdlog
)

target_link_libraries(NthuRoute PRIVATE
    Boost::boost
    ZLIB::ZLIB
    pthread
)

if(OpenMP_CXX_FOUND)
    target_link_libraries(NthuRoute PRIVATE OpenMP::OpenMP_CXX)
    target_compile_definitions(NthuRoute PRIVATE NTHU_ROUTE_OPENMP=1)
endif()

if(NTHU_ROUTE_CUDA_DOGLEG)
    target_compile_definitions(NthuRoute PRIVATE NTHU_ROUTE_CUDA_DOGLEG=1)
    set_source_files_properties(src/router/CudaDogleg.cu PROPERTIES LANGUAGE CUDA)
    set_target_properties(NthuRoute PROPERTIES
        CUDA_STANDARD 14
        CUDA_STANDARD_REQUIRED ON
        CUDA_ARCHITECTURES "70;75;80;86"
        CUDA_SEPARABLE_COMPILATION OFF
    )
    target_compile_options(NthuRoute PRIVATE
        $<$<COMPILE_LANGUAGE:CUDA>:-O3>
    )
endif()

# Compiler warnings for project code
target_compile_options(NthuRoute PRIVATE
    $<$<COMPILE_LANGUAGE:CXX>:-Wall>
    $<$<COMPILE_LANGUAGE:CXX>:-Wextra>
    $<$<COMPILE_LANGUAGE:CXX>:-Wpedantic>
    $<$<COMPILE_LANGUAGE:CXX>:-Wnull-dereference>
    $<$<COMPILE_LANGUAGE:CXX>:-Wformat=2>
)

# Default build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG")
set(CMAKE_CXX_FLAGS_DEBUG "-g -O0")

# Install target
install(TARGETS NthuRoute DESTINATION bin)

# Copy data files needed at runtime
configure_file(${CMAKE_SOURCE_DIR}/POWV9.dat ${CMAKE_BINARY_DIR}/POWV9.dat COPYONLY)
configure_file(${CMAKE_SOURCE_DIR}/POST9.dat ${CMAKE_BINARY_DIR}/POST9.dat COPYONLY)

# --- Tests ---
find_package(GTest QUIET)
if(GTest_FOUND)
    enable_testing()

    # Library of project sources (without Main.cpp) for tests to link against
    set(LIB_SOURCES ${PROJECT_SOURCES})
    list(REMOVE_ITEM LIB_SOURCES src/router/Main.cpp)

    add_executable(NthuRouteTests
        tests/test_geometry.cpp
        tests/test_routing_component.cpp
        tests/test_datadef.cpp
        tests/test_routing_region.cpp
        tests/test_edge_plane.cpp
        tests/test_flute.cpp
        ${LIB_SOURCES}
    )

    target_include_directories(NthuRouteTests PRIVATE
        ${CMAKE_SOURCE_DIR}/src
        ${Boost_INCLUDE_DIRS}
    )

    target_include_directories(NthuRouteTests SYSTEM PRIVATE
        ${CMAKE_SOURCE_DIR}/src/spdlog
    )

    target_link_libraries(NthuRouteTests PRIVATE
        GTest::GTest
        GTest::Main
        Boost::boost
        ZLIB::ZLIB
        pthread
    )

    if(OpenMP_CXX_FOUND)
        target_link_libraries(NthuRouteTests PRIVATE OpenMP::OpenMP_CXX)
        target_compile_definitions(NthuRouteTests PRIVATE NTHU_ROUTE_OPENMP=1)
    endif()

    target_compile_options(NthuRouteTests PRIVATE
        -Wall
        -Wextra
        -Wpedantic
        -Wnull-dereference
        -Wformat=2
    )

    include(GoogleTest)
    gtest_discover_tests(NthuRouteTests)
endif()
