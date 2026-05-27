cmake_minimum_required(VERSION 3.18)

project(hpc_final_router LANGUAGES CXX)

option(ROUTER_ENABLE_CUDA "Build CUDA candidate router when nvcc is available" ON)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(router_core
  src/router.cpp
)
target_include_directories(router_core PUBLIC include)
target_compile_options(router_core PRIVATE
  $<$<CXX_COMPILER_ID:GNU,Clang>:-O3 -Wall -Wextra -Wpedantic>
)

add_executable(router_bench
  src/main.cpp
)
target_link_libraries(router_bench PRIVATE router_core)
target_compile_options(router_bench PRIVATE
  $<$<CXX_COMPILER_ID:GNU,Clang>:-O3 -Wall -Wextra -Wpedantic>
)

if(ROUTER_ENABLE_CUDA)
  include(CheckLanguage)
  check_language(CUDA)
  if(CMAKE_CUDA_COMPILER)
    enable_language(CUDA)
    target_sources(router_core PRIVATE src/cuda_router.cu)
    target_compile_definitions(router_core PUBLIC ROUTER_WITH_CUDA=1)
    set_source_files_properties(src/cuda_router.cu PROPERTIES LANGUAGE CUDA)
    set_target_properties(router_core PROPERTIES
      CUDA_STANDARD 17
      CUDA_STANDARD_REQUIRED ON
      CUDA_ARCHITECTURES "70;75;80;86"
      CUDA_SEPARABLE_COMPILATION OFF
    )
    target_compile_options(router_core PRIVATE
      $<$<COMPILE_LANGUAGE:CUDA>:-O3 --use_fast_math>
    )
  else()
    message(STATUS "CUDA compiler not found; building CPU-only router_bench")
    target_compile_definitions(router_core PUBLIC ROUTER_WITH_CUDA=0)
  endif()
else()
  target_compile_definitions(router_core PUBLIC ROUTER_WITH_CUDA=0)
endif()
