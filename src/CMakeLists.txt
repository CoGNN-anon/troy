file(GLOB_RECURSE CURRENT_HEADERS *.h *.hpp *.cuh ${PROJECT_SOURCE_DIR}/app/*.cuh)
file(GLOB_RECURSE CURRENT_SOURCES *.cpp *.cu *.c ${PROJECT_SOURCE_DIR}/app/*.cu)

source_group("Include" FILES ${CURRENT_HEADERS})
source_group("Source" FILES ${CURRENT_SOURCES})

add_library(troy SHARED ${CURRENT_HEADERS} ${CURRENT_SOURCES})
set_target_properties(troy PROPERTIES CUDA_SEPERABLE_COMPILATION ON)

set(gcc_like_cxx "$<COMPILE_LANG_AND_ID:CXX,ARMClang,AppleClang,Clang,GNU>")
set(nvcc_cxx "$<COMPILE_LANG_AND_ID:CUDA,NVIDIA>")

target_compile_options(troy INTERFACE
  "$<${gcc_like_cxx}:$<BUILD_INTERFACE:-fPIC>>"
  "$<${nvcc_cxx}:$<BUILD_INTERFACE:--compiler-options=-fPIC>>"
)

install(TARGETS troy
  EXPORT troyTargets
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
  RUNTIME DESTINATION bin
  INCLUDES DESTINATION include
)

install(EXPORT troyTargets
        FILE troyTargets.cmake
        NAMESPACE TROY::
        DESTINATION lib/cmake/troy)

file(GLOB MAIN_DIR_HEADERS *.h *.hpp *.cuh)
file(GLOB UTILS_HEADERS utils/*.h utils/*.hpp utils/*.cuh)
file(GLOB APP_HEADERS ${PROJECT_SOURCE_DIR}/app/*.cuh)

install(FILES ${MAIN_DIR_HEADERS} DESTINATION include/troy)
install(FILES ${UTILS_HEADERS} DESTINATION include/troy/utils)
install(FILES ${APP_HEADERS} DESTINATION include/troy/app)

set(INSTALL_DIR "${CMAKE_INSTALL_PREFIX}")
set(BUILD_DIR "${PROJECT_SOURCE_DIR}/build")
include(CMakePackageConfigHelpers)
configure_package_config_file(
	"${CMAKE_CURRENT_SOURCE_DIR}/cmake/troyConfig.cmake.in"
	"${CMAKE_CURRENT_SOURCE_DIR}/cmake/troyConfig.cmake"
	INSTALL_DESTINATION lib/cmake/troy
    PATH_VARS INSTALL_DIR BUILD_DIR)
install(FILES
        "${CMAKE_CURRENT_SOURCE_DIR}/cmake/troyConfig.cmake"
        DESTINATION lib/cmake/troy)