cmake_minimum_required(VERSION 3.5)

# Location of project defined include and FindXXX.cmake files
set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake"
                      "${CMAKE_SOURCE_DIR}/cmake/Modules"
                      "${CMAKE_SOURCE_DIR}/cmake/Utils")

include(NoInSourceBuild)

project(Truchas VERSION 3.1.0 LANGUAGES C Fortran)

# Append a pre-release tag to the version if needed
set(Truchas_PRERELEASE alpha)
if(Truchas_PRERELEASE)
  string(APPEND Truchas_VERSION -${Truchas_PRERELEASE})
endif()

# Fix a few things that cmake gets wrong for the NAG compiler.
if(CMAKE_Fortran_COMPILER_ID MATCHES "NAG")
  set(CMAKE_Fortran_COMPILE_OPTIONS_PIE "-PIC")
  include(NAGFortranCompilerVersion)
endif()

# Create all the Fortran module files in a directory at the root build directory
set(Truchas_MODULE_DIR ${Truchas_BINARY_DIR}/modules)
set(CMAKE_Fortran_MODULE_DIRECTORY ${Truchas_MODULE_DIR})

# ---------------------------------------------------------------------------- #
# Build Options 
# ---------------------------------------------------------------------------- #

# Validate a user-supplied value for CMAKE_BUILD_TYPE.
if(CMAKE_BUILD_TYPE)
  string(TOUPPER "${CMAKE_BUILD_TYPE}" CMAKE_BUILD_TYPE_UC)
  if(NOT "${CMAKE_BUILD_TYPE_UC}" MATCHES "^(DEBUG|RELEASE|RELWITHDEBINFO|MINSIZEREL)$")
    message(FATAL_ERROR "CMAKE_BUILD_TYPE must be {Debug|Release|RelWithDebInfo|MinSizeRel}")
  endif()
endif()

# Build with MPI
option(ENABLE_MPI "Build the parallel (MPI) library" True)

# Build with support for dynamic loading of user functions
option(ENABLE_DYNAMIC_LOADING "Build with support for dynamic loading of user functions" True)

# Build with PIC (position in code)
option(WITH_PIC "Build with PIC support" True)
if(WITH_PIC)
  set(CMAKE_POSITION_INDEPENDENT_CODE True)
endif()

# Build shared libs
option(ENABLE_SHARED "Build shared libraries" True)
if(ENABLE_SHARED)
  set(BUILD_SHARED_LIBS True)
else()
  set(BUILD_SHARED_LIBS False)
  set(CMAKE_FIND_LIBRARY_SUFFIXES ".a")
  set(CMAKE_EXE_LINKER_FLAGS "-static")
endif()

# Strip RPATH from installed binaries/libraries 
option(ENABLE_INSTALL_RPATH "Use RPATH in installed binaries and libraries" True)

# ---------------------------------------------------------------------------- #
# External Dependencies 
# ---------------------------------------------------------------------------- #

# MPI
if(ENABLE_MPI)
  find_package(MPI REQUIRED)
endif()

# Python and NumPy
find_package(PythonInterp REQUIRED)
set(_tmp "${CMAKE_FIND_LIBRARY_SUFFIXES}")
set(CMAKE_FIND_LIBRARY_SUFFIXES ".a;.so")
find_package(PythonLibs REQUIRED)
set(CMAKE_FIND_LIBRARY_SUFFIXES "${_tmp}")
find_package(NumPy)

# BLAS and LAPACK -- these are not required
find_package(LAPACK)
find_package(BLAS)

# Rest are external dependencies that can be provided by the Truchas TPL build

set(CMAKE_PREFIX_PATH ${TRUCHAS_TPL_DIR})

# HYPRE library
find_package(HYPRE 2.6.0 EXACT)
if(HYPRE_FOUND)
  if(ENABLE_MPI)
    if(NOT HYPRE_IS_PARALLEL)
      set(HYPRE_FOUND False)
      message(STATUS "Require parallel HYPRE library but found unsuitable serial library")
    endif()
  else()
    if(HYPRE_IS_PARALLEL)
      set(HYPRE_FOUND False)
      message(STATUS "Require serial HYPRE library but found unsuitable parallel library")
    endif()
  endif()
endif()
if(NOT HYPRE_FOUND)
  message(FATAL_ERROR "Could NOT find a suitable Hypre installation")
endif()

# HDF5 library
if(ENABLE_MPI)
  set(HDF5_PREFER_PARALLEL True)
endif()
find_package(HDF5 "1.8.8" COMPONENTS C HL)
if(HDF5_FOUND)
  if(ENABLE_MPI)
    if(NOT HDF5_IS_PARALLEL)
      set(HDF5_FOUND False)
      message(STATUS "Require parallel HDF5 library but found unsuitable serial library")
    endif()
  else()
    if(HDF5_IS_PARALLEL)
      set(HDF5_FOUND False)
      message(STATUS "Require serial HDF5 library but found unsuitable parallel library")
    endif()
  endif()
endif()
if(HDF5_FOUND)
  add_library(hdf5 INTERFACE)
  target_link_libraries(hdf5 INTERFACE ${HDF5_LIBRARIES})
  target_include_directories(hdf5 INTERFACE ${HDF5_INCLUDE_DIRS})
  target_compile_definitions(hdf5 INTERFACE ${HDF5_DEFINITIONS})
else()
  message(FATAL_ERROR "Could NOT find a suitable HDF5 installation")
endif()

# NetCDF library
find_package(NetCDF "4.1.3")
if(NETCDF_FOUND)
  if(NOT NETCDF_HAS_NC4)
    message(STATUS "Found unsuitable NetCDF without the required netcdf-4 feature")
    set(NETCDF_FOUND False)
  endif()
endif()
if(NOT NETCDF_FOUND)
  message(FATAL_ERROR "Could NOT find a suitable NetCDF installation")
endif()

# ExodusII library
find_package(Exodus "514")
if(NOT EXODUS_FOUND)
  message(FATAL_ERROR "Could NOT find a suitable Exodus installation")
endif()

# Petaca library and its dependency libyajl
find_package(PETACA)
if(NOT PETACA_FOUND)
  message(FATAL_ERROR "Could NOT find a suitable Petaca installation")
endif()

# SWIG program
find_package(SWIG)
if(SWIG_FOUND)
  if(SWIG_VERSION VERSION_LESS "2" OR NOT (SWIG_VERSION VERSION_LESS "3"))
    set(SWIG_FOUND FALSE)
    message(STATUS "Could NOT find a suitable SWIG: version 2 is required")
  endif()
endif()
if(NOT SWIG_FOUND)
  message(FATAL_ERROR "Could NOT find a suitable swig executable")
endif()

# Test - need a swith here to enable testing
enable_testing()

# The value of SERIAL_COMMAND_PREFACE will preface the command line of serial
# unit tests.  Normally this is empty, but in the Cray Linux environment.
if(CRAY)
  set(SERIAL_COMMAND_PREFACE ${MPIEXEC} ${MPIEXEC_NUMPROC_FLAG} 1)
else()
  set(SERIAL_COMMAND_PREFACE)
endif()

# ---------------------------------------------------------------------------- #
# Preprocessor definitions 
# ---------------------------------------------------------------------------- #

# Preprocessor - allow this to be a list to define global flags easily
if(NOT Truchas_PREPROCESSOR)
  set(Truchas_PREPROCESSOR cpp -traditional-cpp)
endif()

# Turn off assertions in Truchas Fortran code
if(CMAKE_BUILD_TYPE)
  if(${CMAKE_BUILD_TYPE} STREQUAL "Release")
    list(APPEND Truchas_PREPROCESSOR -DNDEBUG)
  endif()
endif()

# Add the compiler type to the global defines and the preprocessor
string(TOUPPER "-D${CMAKE_Fortran_COMPILER_ID}_COMPILER" Truchas_Compiler_Define)
add_definitions(${Truchas_Compiler_Define} ${Truchas_Compiler_Define}_WORKAROUND)
list(APPEND Truchas_PREPROCESSOR 
            ${Truchas_Compiler_Define}
            ${Truchas_Compiler_Define}_WORKAROUND)

# Specific compiler bug workarounds and defines. These are used by
# the custom Fortran preprocessing step (that need to be eliminated).
if(CMAKE_Fortran_COMPILER_ID MATCHES Intel)
  list(APPEND Truchas_PREPROCESSOR -DNO_2008_LHS_POLY_REALLOC)
  list(APPEND Truchas_PREPROCESSOR -DINTEL_DPD200237439)
  list(APPEND Truchas_PREPROCESSOR -DINTEL_DPD200362026)
  if(CMAKE_Fortran_COMPILER_VERSION VERSION_LESS "16.0.0")
    list(APPEND Truchas_PREPROCESSOR -DINTEL_INTEGER_SET_ICE)
  endif()
  if(CMAKE_Fortran_COMPILER_VERSION VERSION_GREATER "14.0.3" AND
      CMAKE_Fortran_COMPILER_VERSION VERSION_LESS "15.0.2")
    list(APPEND Truchas_PREPROCESSOR -DINTEL_DPD200362104)
  endif()
endif()

if(ENABLE_DYNAMIC_LOADING)
  list(APPEND Truchas_PREPROCESSOR -DENABLE_DYNAMIC_LOADING)
endif()

# Specific compiler bug workarounds and defines.
# These are used when compiling code that has not been preprocessed.
if(CMAKE_Fortran_COMPILER_ID MATCHES Intel)
  add_definitions(-DNO_2008_LHS_POLY_REALLOC)
  add_definitions(-DINTEL_DPD200237439)
endif()

# More hardcoded defines - only used in drivers.f90 need to move
string(TIMESTAMP Truchas_BUILD_DATE "%Y-%m-%d %H:%M:%S")
site_name(Truchas_HOSTNAME)
list(APPEND Truchas_PREPROCESSOR -DVERSION='${Truchas_VERSION}')
list(APPEND Truchas_PREPROCESSOR -DBUILD_DATE='${Truchas_BUILD_DATE}')
list(APPEND Truchas_PREPROCESSOR -DHOST_NAME='${Truchas_HOSTNAME}')
list(APPEND Truchas_PREPROCESSOR -DARCHITECTURE='${CMAKE_SYSTEM_PROCESSOR}')
if(CMAKE_BUILD_TYPE)
  list(APPEND Truchas_PREPROCESSOR "-DCOMPILER_FLAGS='${CMAKE_Fortran_FLAGS} ${CMAKE_Fortran_FLAGS_${CMAKE_BUILD_TYPE_UC}}'")
else()
  list(APPEND Truchas_PREPROCESSOR -DCOMPILER_FLAGS='${CMAKE_Fortran_FLAGS}')
endif()

# Add any user defined preprocessor flags
if (Truchas_FPP_FLAGS)
  list(APPEND Truchas_PREPROCESSOR ${Truchas_FPP_FLAGS})
endif()

# ---------------------------------------------------------------------------- #
# Installation Definitions 
# ---------------------------------------------------------------------------- #

# Need the paths defined before adding src to the build

# Define the build id
include(GetTruchasBuildId)
get_truchas_build_id(Truchas_BUILD_ID)

# Default installation location is the Truchas_SOURCE_DIR
set(Truchas_DFLT_INSTALL_PREFIX ${Truchas_SOURCE_DIR}/install/${Truchas_BUILD_ID})
if (CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX ${Truchas_DFLT_INSTALL_PREFIX}
      CACHE PATH "Installation prefix" FORCE)
endif()

# Binary installation path, override with -D Truchas_BIN_INSTALL_DIR
if (NOT Truchas_BIN_INSTALL_DIR)
  set(Truchas_BIN_INSTALL_DIR ${CMAKE_INSTALL_PREFIX}/bin)
endif()

# Library installation path, override with -D Truchas_LIBRARY_INSTALL_DIR
if (NOT Truchas_LIBRARY_INSTALL_DIR)
  set(Truchas_LIBRARY_INSTALL_DIR ${CMAKE_INSTALL_PREFIX}/lib)
endif()

# Module installation path, override with -D Truchas_MODULE_INSTALL_DIR
if (NOT Truchas_MODULE_INSTALL_DIR)
  set(Truchas_MODULE_INSTALL_DIR ${CMAKE_INSTALL_PREFIX}/include)
endif()

# Copy entire include directory to  Truchas_MODULE_INSTALL_DIR
install(CODE "MESSAGE(STATUS \"Installing: modules in ${Truchas_MODULE_INSTALL_DIR}\")")
install(CODE
        "EXECUTE_PROCESS ( COMMAND \"${CMAKE_COMMAND}\" -E copy_directory \"${Truchas_MODULE_DIR}\" \"${Truchas_MODULE_INSTALL_DIR}\")"
)

# Configuration (CMake) file installation location
if (NOT Truchas_CONFIG_INSTALL_DIR)
  set(Truchas_CONFIG_INSTALL_DIR ${CMAKE_INSTALL_PREFIX}/share/cmake/truchas)
endif()

# ---------------------------------------------------------------------------- #
# RPATH handling  (http://www.cmake.org/Wiki/CMake_RPATH_handling) 
# ---------------------------------------------------------------------------- #

# use, i.e. don't skip the full RPATH for the build tree
SET(CMAKE_SKIP_BUILD_RPATH  FALSE)

# when building, don't use the install RPATH already
# (but later on when installing)
SET(CMAKE_BUILD_WITH_INSTALL_RPATH FALSE) 

# Library install directories
set(Truchas_LIBRARY_INSTALL_DIRS
     ${Truchas_LIBRARY_INSTALL_DIR}
     ${TRUCHAS_TPL_DIR}/lib)

# Add RPATH to binaries,libraries, *so, etc.   
if (ENABLE_INSTALL_RPATH)

  # Only want non-system paths 
  foreach(dir ${Truchas_LIBRARY_INSTALL_DIRS})
    list(FIND CMAKE_PLATFORM_IMPLICIT_LINK_DIRECTORIES "${dir}" isSystemDir)
    if("${isSystemDir}" STREQUAL "-1")
       list(APPEND CMAKE_INSTALL_RPATH "${dir}")
    endif("${isSystemDir}" STREQUAL "-1")
  endforeach()

  # add the automatically determined parts of the RPATH
  # which point to directories outside the build tree to the install RPATH
  set(CMAKE_INSTALL_RPATH_USE_LINK_PATH True)

endif()  
 
# ---------------------------------------------------------------------------- #
# Source Directories 
# ---------------------------------------------------------------------------- #

add_subdirectory(src)
add_subdirectory(test)

# ---------------------------------------------------------------------------- #
# Export Definitions 
# ---------------------------------------------------------------------------- #

# Create the target file
#set(Truchas_TARGETS_FILE truchas-targets.cmake)
#export(truchas truchas_exe FILE ${Truchas_TARGETS_FILE})

# Create truchas-config.cmake (find_package(Truchas))
#set(Truchas_CONFIG_FILE ${Truchas_BINARY_DIR}/truchas-config.cmake)
#configure_file(${Truchas_SOURCE_DIR}/truchas-config.in
#               ${Truchas_CONFIG_FILE}
#	       @ONLY)
#install(FILES ${Truchas_CONFIG_FILE} ${Truchas_TARGETS_FILE} 
#        DESTINATION ${Truchas_CONFIG_INSTALL_DIR})

# ---------------------------------------------------------------------------- #
# Package Definitions 
# ---------------------------------------------------------------------------- #

# Package name
set(CPACK_PACKAGE_NAME truchas)

# Version information
set(CPACK_PACKAGE_VERSION_MAJOR "${Truchas_VERSION_MAJOR}")
set(CPACK_PACKAGE_VERSION_MINOR "${Truchas_VERSION_MINOR}")
set(CPACK_PACKAGE_VERSION_PATCH "${Truchas_VERSION_PATCH}")
set(CPACK_PACKAGE_VERSION       "${Truchas_VERSION}")

# Basic package information
set(CPACK_PACKAGE_FILE_NAME "truchas-${Truchas_VERSION}-${CMAKE_SYSTEM_NAME}")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Truchas: Cool code package")
set(CPACK_PACKAGE_VENDOR "Los Alamos National Laboratory")
set(CPACK_RESOURCE_FILE_LICENSE ${Truchas_SOURCE_DIR}/LICENSE.md)

# Name of the source file distribution 
set(CPACK_SOURCE_PACKAGE_FILE_NAME "truchas-${Truchas_VERSION}"
    CACHE INTERNAL "Distribution base file name")

# Gzip tar files are defined as my generator, many other options are available
set(CPACK_SOURCE_GENERATOR TGZ)  
  
# Files to ignore regular expressions are allowed
set(CPACK_SOURCE_IGNORE_FILES
     "/\\\\.hg/"
     "/CVS/"
     "/\\\\.svn/"
     "\\\\.swp$"
     "/install/"
     "/build/"
     "Makefile"
     "/CMakeFiles/"
     "CMakeCache.txt"
     "cmake_install.cmake")

# This will add a 'package' and 'package_source' targets
include(CPack)

# Print a summary of the build configuration
include(configuration_summary)
