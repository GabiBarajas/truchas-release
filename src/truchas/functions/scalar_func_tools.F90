!!
!! SCALAR_FUNC_TOOLS
!!
!! A collection of procedures deriving new SCALAR_FUNC objects from existing
!! ones, and other general utility procedures.
!!
!! Neil N. Carlson <nnc@lanl.gov>
!! Adapted for F2008, April 2014
!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!
!! Copyright (c) Los Alamos National Security, LLC.  This file is part of the
!! Truchas code (LA-CC-15-097) and is subject to the revised BSD license terms
!! in the LICENSE file found in the top-level directory of this distribution.
!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!
!! PROGRAMMING INTERFACE
!!
!!  IS_CONST(F) returns true if the dynamic type of the polymorphic SCALAR_FUNC
!!    argument F is CONST_SCALAR_FUNC (and so is a constant-valued function).
!!
!!  CALL ALLOC_SCALAR_FUNC_ANTIDERIV (F, X0, G0, G, STAT, ERRMSG) instantiates
!!    the antiderivative of the given function.  F and G are class SCALAR_FUNC
!!    variables; G is allocatable and the antiderivative of F is returned in G,
!!    which satisfies the condition G%EVAL([X0]) == G0.  The dynamic type of F
!!    is limited to those where the antiderivative is easily determined.
!!    Currently that is constant (CONST_SCALAR_FUNC), single-variable
!!    polynomials (POLY_SCALAR_FUNC) containing no 1/x term, and tabular
!!    functions (TABULAR_SCALAR_FUNC). If F is otherwise, a non-zero value is
!!    returned in STAT, and an explanatory error message is returned in the
!!    deferred-length allocatable character variable ERRMSG.
!!
!!  CALL ALLOC_SCALAR_FUNC_PRODUCT (F, G, FG, STAT, ERRMSG) instantiates a new
!!    function that is the product of the given class SCALAR_FUNC objects F
!!    and G.  The product function is returned in the allocatable SCALAR_FUNC
!!    variable FG.  The allowed dynamic types of F and G are very limited:
!!    F must be constant (CONST_SCALAR_FUNC) and G must be either constant or
!!    a single or multi-variable polynomial (POLY_SCALAR_FUNC or MPOLY_SCALAR_FUNC).
!!    If F or G is otherwise, a non-zero value is returned in STAT, and an
!!    explanatory error message is returned in the deferred-length allocatable
!!    character variable ERRMSG.
!!

#include "f90_assert.fpp"

module scalar_func_tools

  use kinds, only: r8
  use scalar_func_class
  implicit none
  private

  public :: is_const
  public :: alloc_scalar_func_antideriv, alloc_scalar_func_product

contains

  logical function is_const (f)
    use const_scalar_func_type
    class(scalar_func), intent(in) :: f
    select type (f)
    type is (const_scalar_func)
      is_const = .true.
    class default
      is_const = .false.
    end select
  end function is_const

  subroutine alloc_scalar_func_antideriv (f, x0, g0, g, stat, errmsg)

    use const_scalar_func_type
    use poly_scalar_func_type
    use tabular_scalar_func_type
    use scalar_func_factories

    class(scalar_func), intent(in) :: f
    real(r8), intent(in) :: x0, g0
    class(scalar_func), allocatable, intent(out) :: g
    integer, intent(out) :: stat
    character(:), allocatable, intent(out) :: errmsg

    integer :: j, n
    integer,  allocatable :: e(:)
    real(r8), allocatable :: c(:)

    select type (f)
    type is (const_scalar_func)

      call alloc_poly_scalar_func (g, c=[g0,f%const], e=[0,1], x0=x0)

    type is (tabular_scalar_func)

      if (allocated(f%t)) then
        stat = -1
        errmsg = 'unable to create antiderivative for a smoothed tabular function'
        return
      end if
      call alloc_tabular_ad_scalar_func (g, f, x0, g0)

    type is (poly_scalar_func)

      if (f%emin < 0) then
        if (f%c(-1) /= 0.0_r8) then
          stat = -1
          errmsg = 'unable to create antiderivative for poly with 1/x term'
          return
        end if
      end if
      n = count(f%c /= 0.0_r8)
      if (g0 /= 0.0_r8) n = n + 1
      allocate(c(n), e(n))
      n = 0
      do j = f%emin, f%emax
        if (f%c(j) /= 0.0_r8) then
          n = n + 1
          c(n) = f%c(j)/(j+1)
          e(n) = j + 1
        end if
      end do
      if (g0 /= 0.0_r8) then
        n = n + 1
        c(n) = g0
        e(n) = 0
      end if
      call alloc_poly_scalar_func (g, c, e, f%x0)
      deallocate(c, e)

    class default

      stat = -1
      errmsg = 'cannot create antiderivative for this type of function'
      return

    end select

    stat = 0

  end subroutine alloc_scalar_func_antideriv

  subroutine alloc_scalar_func_product (f, g, fg, stat, errmsg)

    use const_scalar_func_type
    use poly_scalar_func_type
    use mpoly_scalar_func_type
    use tabular_scalar_func_type
    use scalar_func_factories

    class(scalar_func), intent(in) :: f, g
    class(scalar_func), allocatable, intent(out) :: fg
    integer, intent(out) :: stat
    character(:), allocatable, intent(out) :: errmsg

    select type (f)
    type is (const_scalar_func)
      !fg = g
      allocate(fg, source=g)
      select type (fg)
      type is (const_scalar_func)
        fg%const = f%const * fg%const
      type is (poly_scalar_func)
        fg%c = f%const * fg%c
      type is (mpoly_scalar_func)
        fg%coef = f%const * fg%coef
      type is (tabular_scalar_func)
        fg%y = f%const * fg%y
        if (allocated(fg%t)) fg%t = f%const * fg%t
      type is (tabular_ad_scalar_func)
        fg%y = f%const * fg%y
        fg%c = f%const * fg%c
      class default
        stat = -1
        errmsg = 'cannot create product for this type of second function argument'
        return
      end select
    class default
      stat = -1
      errmsg = 'first function argument must be of type const_scalar_func'
      return
    end select

    stat = 0

  end subroutine alloc_scalar_func_product

end module scalar_func_tools
