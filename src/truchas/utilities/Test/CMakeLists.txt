project(UtilitiesTest Fortran)

include(CTest)

# Want test modules in the build directory.
unset(CMAKE_Fortran_MODULE_DIRECTORY)

include_directories(${Truchas_MODULE_DIR})
#include_directories(${PGSLib_MODULE_DIR})

if(CMAKE_Fortran_COMPILER_ID MATCHES Intel)
  if (CMAKE_Fortran_COMPILER_VERSION VERSION_LESS "16.0.0")
    set_source_files_properties(test_integer_set_type.F90 PROPERTIES
                                COMPILE_FLAGS "-assume realloc_lhs -DINTEL_INTEGER_SET_ICE")
  else()
    set_source_files_properties(test_integer_set_type.F90 PROPERTIES
                                COMPILE_FLAGS "-assume realloc_lhs")
  endif()
  set_source_files_properties(test_graph_type.F90 PROPERTIES
                              COMPILE_FLAGS "-assume realloc_lhs")
endif()

add_executable(test_integer_set_type test_integer_set_type.F90)
target_link_libraries(test_integer_set_type truchas ${Truchas_LINK_LIBS})

add_test(integer_set_type ${SERIAL_COMMAND_PREFACE}
         ${CMAKE_CURRENT_BINARY_DIR}/test_integer_set_type)

set_tests_properties(integer_set_type PROPERTIES PROCESSORS 1)
set_property(TEST integer_set_type PROPERTY LABELS UNIT)

add_executable(test_graph_type test_graph_type.F90)
target_link_libraries(test_graph_type truchas ${Truchas_LINK_LIBS})

add_test(graph_type ${SERIAL_COMMAND_PREFACE}
         ${CMAKE_CURRENT_BINARY_DIR}/test_graph_type)

set_tests_properties(graph_type PROPERTIES PROCESSORS 1)
set_property(TEST graph_type PROPERTY LABELS UNIT)

add_executable(test_permutations test_permutations.F90)
target_link_libraries(test_permutations truchas ${Truchas_LINK_LIBS})

add_test(permutations ${SERIAL_COMMAND_PREFACE}
         ${CMAKE_CURRENT_BINARY_DIR}/test_permutations)

set_tests_properties(permutations PROPERTIES PROCESSORS 1)
set_property(TEST permutations PROPERTY LABELS UNIT)
