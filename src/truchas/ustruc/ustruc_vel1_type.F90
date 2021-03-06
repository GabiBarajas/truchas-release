!!
!! USTRUC_VEL1_TYPE
!!
!! A concrete implementation of USTRUC_PLUGIN/USTRUC_COMP that adds the
!! computation of the solidification front velocity.
!!
!! Neil N. Carlson <nnc@lanl.gov>
!! August 2014
!!
!! PROGRAMMING INTERFACE
!!
!! See the comments that accompany the source for the USTRUC_COMP and
!! USTRUC_PLUGIN classes which define the interface to this object.  The
!! only public entity provided by the module is the following function.
!!
!!  NEW_USTRUC_VEL1(COMP, PARAMS) returns a pointer to a new USTRUC_COMP class
!!    object whose dynamic type is USTRUC_VEL1.  The USTRUC_VEL1 type is itself
!!    private.  COMP is a USTRUC_COMP pointer whose target is being wrapped by
!!    this new analysis component specified by PARAMS.  The new object takes
!!    ownership of the target.  PARAMS is a PARAMETER_LIST object; the relevant
!!    parameters in PARAMS are:
!!
!!      'vel-lo-solid-frac', 'vel-hi-solid-frac' -- velocities are only
!!          computed when the solid fraction lies within the interval defined
!!          by these two values.
!!      'vel-max' -- the maximum computed velocity magnitude; any velocity
!!          computed to have a magnitude greater than or equal to this value
!!          is regarded as invalid.
!!
!! Objects of this type respond to the following data names in the generic
!! GET subroutine: 'velocity', 'speed', and 'invalid-velocity'.
!!

#include "f90_assert.fpp"

module ustruc_vel1_type

  use kinds, only: r8
  use ustruc_plugin_class
  implicit none
  private

  public :: new_ustruc_vel1

  type, extends(ustruc_plugin) :: ustruc_vel1
    real(r8) :: vmax, theta1, theta2
    ! the state arrays are in the core component
  contains
    procedure :: set_state
    procedure :: update_state
    procedure :: get_comp_list
    procedure :: has
    procedure :: getl1
    procedure :: getr1
    procedure :: getr2
    procedure :: serialize
    procedure :: deserialize
  end type ustruc_vel1

#ifndef INTEL_COMPILER_WORKAROUND
  !! Number of bytes (per cell) of internal state for serialization/deserialization
  type(ustruc_vel1), allocatable :: dummy  ! only use is in the following parameter declaration
  integer, parameter :: NBYTES = storage_size(dummy%core%speed)/8 + &
                               3*storage_size(dummy%core%velocity)/8 + &
                                 storage_size(dummy%core%invalid_velocity)/8
#endif

contains

  function new_ustruc_vel1 (comp, params) result (this)

    use parameter_list_type

    class(ustruc_comp), pointer, intent(in) :: comp
    type(parameter_list) :: params
    type(ustruc_vel1), pointer :: this

    allocate(this)
    call this%init (comp)

    call params%get ('vel-lo-solid-frac', this%theta1)
    INSIST(this%theta1 > 0.0_r8)
    call params%get ('vel-hi-solid-frac', this%theta2)
    INSIST(this%theta2 < 1.0_r8)
    INSIST(this%theta1 <= this%theta2)
    call params%get ('vel-max', this%vmax)
    INSIST(this%vmax >= 0.0_r8)

    associate (core => this%core, n => this%n)
      allocate(core%invalid_velocity(n), core%velocity(3,n), core%speed(n))
    end associate

  end function new_ustruc_vel1

  subroutine set_state (this, t, temp, temp_grad, frac, frac_grad, invalid)

    class(ustruc_vel1), intent(inout) :: this
    real(r8), intent(in) :: t, temp(:), temp_grad(:,:), frac(:), frac_grad(:,:)
    logical,  intent(in) :: invalid(:)

    call this%ustruc_plugin%set_state (t, temp, temp_grad, frac, frac_grad, invalid)

    associate (core => this%core)
      core%invalid_velocity = .true.
      core%velocity = 0.0_r8
      core%speed = 0.0_r8
    end associate

  end subroutine set_state

  subroutine update_state (this, t, temp, temp_grad, frac, frac_grad, invalid)

    class(ustruc_vel1), intent(inout) :: this
    real(r8), intent(in) :: t, temp(:), temp_grad(:,:), frac(:), frac_grad(:,:)
    logical,  intent(in) :: invalid(:)

    integer  :: j
    real(r8) :: grad_norm

    call this%ustruc_plugin%update_state (t, temp, temp_grad, frac, frac_grad, invalid)

    do j = 1, this%n
      this%core%invalid_velocity(j) = .true.
      this%core%velocity(:,j) = 0.0_r8
      this%core%speed(j) = 0.0_r8
      if (invalid(j)) cycle
      if (frac(j) >= this%theta1 .and. frac(j) <= this%theta2) then
        grad_norm = this%vector_magnitude(this%core%frac_grad(:,j))
        if (abs(this%core%frac_rate(j)) <= this%vmax * grad_norm) then
          this%core%speed(j) = this%core%frac_rate(j) / grad_norm
          this%core%velocity(:,j) = -this%core%speed(j) * (this%core%frac_grad(:,j)/grad_norm)
          this%core%invalid_velocity(j) = .false.
        end if
      end if
    end do

  end subroutine update_state

  subroutine get_comp_list (this, list)
    class(ustruc_vel1), intent(in) :: this
    integer, allocatable, intent(out) :: list(:)
    integer, allocatable :: rest(:)
    call this%ustruc_plugin%get_comp_list (rest)
    allocate(list(size(rest)+1))
    list(1) = USTRUC_VEL1_ID
    list(2:) = rest
  end subroutine get_comp_list

  subroutine getl1 (this, name, array)
    class(ustruc_vel1), intent(in) :: this
    character(*), intent(in) :: name
    logical, intent(out) :: array(:)
    select case (name)
    case ('invalid-velocity')
      ASSERT(size(array) == size(this%core%invalid_velocity))
      array = this%core%invalid_velocity
    case default
      call this%ustruc_plugin%get (name, array)
    end select
  end subroutine getl1

  logical function has (this, name)
    class(ustruc_vel1), intent(in) :: this
    character(*), intent(in) :: name
    select case (name)
    case ('speed', 'velocity')
      has = .true.
    case default
      has = this%ustruc_plugin%has (name)
    end select
  end function has

  subroutine getr1 (this, name, array, invalid)
    class(ustruc_vel1), intent(in) :: this
    character(*), intent(in) :: name
    real(r8), intent(out) :: array(:)
    logical, intent(out), optional :: invalid(:)
    select case (name)
    case ('speed')
      ASSERT(size(array) == size(this%core%speed))
      array = this%core%speed
      if (present(invalid)) then
        ASSERT(size(invalid) == this%n)
        invalid = this%core%invalid_velocity
      end if
    case default
      call this%ustruc_plugin%get (name, array, invalid)
    end select
  end subroutine getr1

  subroutine getr2 (this, name, array, invalid)
    class(ustruc_vel1), intent(in) :: this
    character(*), intent(in) :: name
    real(r8), intent(out) :: array(:,:)
    logical, intent(out), optional :: invalid(:)
    select case (name)
    case ('velocity')
      ASSERT(all(shape(array) == shape(this%core%velocity)))
      array = this%core%velocity
      if (present(invalid)) then
        ASSERT(size(invalid) == this%n)
        invalid = this%core%invalid_velocity
      end if
    case default
      call this%ustruc_plugin%get (name, array, invalid)
    end select
  end subroutine getr2

  subroutine serialize (this, cid, array)

    use,intrinsic :: iso_fortran_env, only: int8
    use serialization_tools, only: copy_to_bytes

    class(ustruc_vel1), intent(in) :: this
    integer, intent(in) :: cid
    integer(int8), allocatable, intent(out) :: array(:,:)

    integer :: j, offset
#ifdef INTEL_COMPILER_WORKAROUND
    integer :: NBYTES
    NBYTES = storage_size(this%core%speed)/8 + &
           3*storage_size(this%core%velocity)/8 + &
             storage_size(this%core%invalid_velocity)/8
#endif

    if (cid == USTRUC_VEL1_ID) then
      allocate(array(NBYTES,this%n))
      do j = 1, this%n
        offset = 0
        call copy_to_bytes (this%core%speed(j), array(:,j), offset)
        call copy_to_bytes (this%core%velocity(:,j), array(:,j), offset)
        call copy_to_bytes (this%core%invalid_velocity(j), array(:,j), offset)
      end do
    else
      call this%ustruc_plugin%serialize (cid, array)
    end if

  end subroutine serialize

  subroutine deserialize (this, cid, array)

    use,intrinsic :: iso_fortran_env, only: int8
    use serialization_tools, only: copy_from_bytes

    class(ustruc_vel1), intent(inout) :: this
    integer, intent(in) :: cid
    integer(int8), intent(in) :: array(:,:)

    integer :: j, offset
#ifdef INTEL_COMPILER_WORKAROUND
    integer :: NBYTES
    NBYTES = storage_size(this%core%speed)/8 + &
           3*storage_size(this%core%velocity)/8 + &
             storage_size(this%core%invalid_velocity)/8
#endif

    if (cid == USTRUC_VEL1_ID) then
      INSIST(size(array,1) == NBYTES)
      INSIST(size(array,2) == this%n)
      do j = 1, this%n
        offset = 0
        call copy_from_bytes (array(:,j), offset, this%core%speed(j))
        call copy_from_bytes (array(:,j), offset, this%core%velocity(:,j))
        call copy_from_bytes (array(:,j), offset, this%core%invalid_velocity(j))
      end do
    else
      call this%ustruc_plugin%deserialize (cid, array)
    end if

  end subroutine deserialize

end module ustruc_vel1_type
