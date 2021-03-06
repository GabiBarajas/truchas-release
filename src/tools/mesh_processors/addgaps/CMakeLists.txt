project(TruchasToolsAddgaps Fortran)

# --- CMake modules
include(FortranPreprocessFiles)

# --- Include paths

# Add the SOURCE_DIR and BINARY_DIR to the include directories
set(CMAKE_INCLUDE_CURRENT_DIR True)

# Truchas module directory
include_directories(${Truchas_MODULE_DIR})

# --- Preprocessor
# To avoid overwriting VERSION
set(ADDGAPS_PREPROCESSOR cpp -traditional-cpp)


# --- AddGaps
fortran_preprocess_files(ADDGAPS_SOURCE_FILES
                         FILES 
			     f90_assert.F90
			     addgaps_proc.F90 
			     command_line.F90
			     addgaps.F90
			 FPP_EXECUTABLE ${ADDGAPS_PREPROCESSOR}
			 FPP_FLAGS -I${TruchasToolsAddgaps_SOURCE_DIR}
			 PROCESS_TARGET ProcessAddgapsFiles)

add_executable(addgaps ${ADDGAPS_SOURCE_FILES})
add_dependencies(addgaps ProcessAddgapsFiles)
target_link_libraries(addgaps truchas ${Truchas_LINK_LIBS})

# --- Install rules 		    
install(TARGETS addgaps
        RUNTIME DESTINATION ${Truchas_BIN_INSTALL_DIR}
        LIBRARY DESTINATION ${Truchas_LIBRARY_INSTALL_DIR}
	ARCHIVE DESTINATION ${Truchas_LIBRARY_INSTALL_DIR})

