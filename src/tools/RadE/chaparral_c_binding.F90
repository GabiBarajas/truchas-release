!!
!! CHAPARRAL_C_BINDING
!!
!! Raw bindings to a subset of the Chaparral library (VF)
!!
!! Neil N. Carlson <nnc@lanl.gov>
!! August 2016, a modernization of chaparral.F90
!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!
!! Copyright (c) Los Alamos National Security, LLC.  This file is part of the
!! Truchas code (LA-CC-15-097) and is subject to the revised BSD license terms
!! in the LICENSE file found in the top-level directory of this distribution.
!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

module chaparral_c_binding

  use,intrinsic :: iso_c_binding, only: c_char, c_int, c_float, c_double, c_null_char
  use,intrinsic :: iso_c_binding, only: c_ptr, c_loc, c_null_ptr
  implicit none
  public

  private :: c_char, c_int, c_float, c_double, VF_DefineEnclosure_c, VF_GetMatrix_c

  integer, parameter :: VF_MATRIX_EXCL_VIRT = 1
  integer, parameter :: VF_MATRIX_EXCL_DIAG = 2

  !! Interface to a wrapper function in chaparral_ext.c which fills in
  !! the MPI communicator argument to the real VF_Setup in Chaparral.
  interface
    subroutine VF_Setup() bind(c,name='VF_SetupDefault')
    end subroutine
  end interface

  !! Interfaces to Chaparral library functions
  interface
    subroutine VF_SetNumEnclosures(nenclosures) bind(c,name='VF_SetNumEnclosures')
      import c_int
      integer(c_int), value :: nenclosures
    end subroutine

    subroutine VF_SetMaxSurfaces(max_surfaces) bind(c,name='VF_SetMaxSurfaces')
      import c_int
      integer(c_int), value :: max_surfaces
    end subroutine

    subroutine VF_CleanUp() bind(c,name='VF_CleanUp')
    end subroutine

    function VF_DefineEnclosure_c(name, nonblocking, partial, asink, npatches, &
        global_ids, debug_level) result(encl) bind(c,name='VF_DefineEnclosure')
      import c_int, c_char, c_double
      character(kind=c_char) :: name(*)
      integer(c_int), value :: nonblocking, partial, npatches, debug_level
      integer(c_int) :: global_ids(*), encl
      real(c_double), value :: asink
    end function

    subroutine VF_RandomizeSurfacesOn() bind(c,name='VF_RandomizeSurfacesOn')
    end subroutine

    subroutine VF_RandomizeSurfacesOff() bind(c,name='VF_RandomizeSurfacesOff')
    end subroutine

    subroutine VF_DefineTopology(enclosure, geom_type, nfacets, nnodes, x, y, z, c, &
        vertex_offset, f2p_map, nrotations, x_mirror, y_mirror, z_mirror, bsp_depth, &
        bsp_length, spatial_tol, debug_level) bind(c,name='VF_DefineTopology')
      import c_int, c_double
      integer(c_int), value :: enclosure, geom_type, nfacets, nnodes
      real(c_double) :: x(*), y(*), z(*)
      integer(c_int) :: c(*), f2p_map(*)
      integer(c_int), value :: vertex_offset, nrotations, x_mirror, y_mirror, z_mirror
      integer(c_int), value :: bsp_depth, bsp_length, debug_level
      real(c_double), value :: spatial_tol
    end subroutine

    subroutine VF_ResetTopology(enclosure) bind(c,name='VF_ResetTopology')
      import c_int
      integer(c_int), value :: enclosure
    end subroutine

    subroutine VF_CalcHemicube(encl, hc_sub_divide, hc_resolution, hc_min_sep) &
        bind(c,name='VF_CalcHemicube')
      import c_int, c_double
      integer(c_int), value :: encl, hc_sub_divide, hc_resolution
      real(c_double), value :: hc_min_sep
    end subroutine

    subroutine VF_CalcPairwise(encl, vis_nsamples, vis_sampling, mc_nsamples, &
        mc_sampling, mc_tol1, mc_tol2) bind(c,name='VF_CalcPairwise')
      import c_int, c_double
      integer(c_int), value :: encl, vis_nsamples, vis_sampling, mc_nsamples, mc_sampling
      real(c_double), value :: mc_tol1, mc_tol2
    end subroutine

    subroutine VF_JitterOn() bind(c,name='VF_JitterOn')
    end subroutine

    subroutine VF_JitterOff() bind(c,name='VF_JitterOff')
    end subroutine

    subroutine VF_SmoothMatrix(encl, wt, tol, max_iter, symmetric, output) &
        bind(c,name='VF_SmoothMatrix')
      import c_int, c_double
      integer(c_int), value :: encl, max_iter, symmetric, output
      real(c_double), value :: wt, tol
    end subroutine

    subroutine VF_OutputMatrixSummaryBanner() bind(c,name='VF_OutputMatrixSummaryBanner')
    end subroutine

    subroutine VF_GetRowCounts(encl, mode, count) bind(c,name='VF_GetRowCounts')
      import c_int
      integer(c_int), value :: encl, mode
      integer(c_int) :: count(*)
    end subroutine

    subroutine VF_GetMatrix_c(encl, vf_cnt, vf_index, vf_data, vf_diag, vf_virt) &
        bind(c,name='VF_GetMatrix')
      import c_int, c_float, c_ptr
      integer(c_int), value :: encl
      integer(c_int) :: vf_cnt(*), vf_index(*)
      real(c_float) :: vf_data(*)
      type(c_ptr), value :: vf_diag, vf_virt ! possibly null (optional) array pointers
    end subroutine
  end interface

contains

  function VF_DefineEnclosure(name, nonblocking, partial, asink, npatches, &
                              global_ids, debug_level) result(encl)
    character(*,kind=c_char) :: name
    integer(c_int) :: nonblocking, partial, npatches, global_ids(:), debug_level, encl
    real(c_double) :: asink
    encl = VF_DefineEnclosure_c(name//c_null_char, nonblocking, partial, asink, &
                                npatches, global_ids, debug_level)
  end function VF_DefineEnclosure

  subroutine VF_GetMatrix(encl, vf_cnt, vf_index, vf_data, vf_diag, vf_virt)
    integer(c_int) :: encl, vf_cnt(:), vf_index(:)
    real(c_float) :: vf_data(:)
    real(c_float), optional, target :: vf_diag(*), vf_virt(*)
    type(c_ptr) :: ptr_vf_diag, ptr_vf_virt
    ptr_vf_diag = c_null_ptr
    if (present(vf_diag)) ptr_vf_diag = c_loc(vf_diag)
    ptr_vf_virt = c_null_ptr
    if (present(vf_virt)) ptr_vf_virt = c_loc(vf_virt)
    call VF_GetMatrix_c(encl, vf_cnt, vf_index, vf_data, ptr_vf_diag, ptr_vf_virt)
  end subroutine VF_GetMatrix

end module chaparral_c_binding
