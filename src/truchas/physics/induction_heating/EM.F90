!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!
!! Copyright (c) Los Alamos National Security, LLC.  This file is part of the
!! Truchas code (LA-CC-15-097) and is subject to the revised BSD license terms
!! in the LICENSE file found in the top-level directory of this distribution.
!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

#include "f90_assert.fpp"

module EM

  use kinds, only: rk => r8
  use parallel_communication
  use EM_data_proxy
  use truchas_logging_services
  implicit none
  private

  public :: initialize_EM, induction_heating

contains

 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 !!
 !! INITIALIZE_EM
 !!
 !! This subroutine performs the initializations needed to calculate the Joule
 !! heat.  This consists of initializing the EM data proxy and defining the
 !! initial Joule heat data.  This data may come from the restart file; if not,
 !! it is computed at time T.  Note that the Joule heat data segment of the
 !! restart file must be dealt with, even if electromagnetics is not enabled.
 !!

  subroutine initialize_EM (t)

    use restart_variables, only: restart
    use restart_driver, only: restart_joule_heat
    use property_module, only:  EM_permittivity, EM_permeability, EM_conductivity

    real(kind=rk), intent(in) :: t

    logical :: jh_defined
    real(kind=rk) :: s
    character(len=10) :: ss

    if (EM_is_on()) then
      call TLS_info (' Initializing electromagnetics ...')
      call init_EM_data_proxy ()
    end if

    !! Process the EM data segment of the restart file if necessary.
    jh_defined = .false.
    if (restart) call restart_joule_heat (jh_defined)

    if (EM_is_off()) return

    !! Push the initial source and EM material parameters into the EM data proxy.
    call set_source_properties (t)
    call init_material_properties
    call set_permittivity (EM_permittivity())
    call set_permeability (EM_permeability())
    call set_conductivity (EM_conductivity())

    if (jh_defined) then

      !! Determine if the restart Joule heat is usable; if not, compute it.
      if (no_source_field()) then
        if (source_has_changed()) then
          call TLS_info ('   Magnetic source field has changed; restart data not usable.')
          call TLS_info ('  No magnetic source field; setting the Joule heat to zero.')
          call zero_joule_power_density ()
        else
          call TLS_info ('   Using the Joule heat data from the restart file.')
        end if
      else if (material_has_changed()) then
        call TLS_info ('   EM material parameters have changed; restart data not usable.')
        call TLS_info ('  Computing the Joule heat ...')
        call compute_joule_heat ()
      else if (source_has_changed()) then
        if (source_is_scaled(s)) then
          write(ss,fmt='(es9.3)') s
          call TLS_info ('   Magnetic source field was scaled by ' // trim(ss) // '; Joule heat scaled accordingly.')
          call scale_joule_power_density (s)
        else
          call TLS_info ('   Magnetic source field has changed; restart data not usable.')
          call TLS_info ('  Computing the Joule heat ...')
          call compute_joule_heat ()
        end if
      else
        call TLS_info ('   Using the Joule heat data from the restart file.')
      end if

    else

      !! Compute the initial Joule heat.
      if (no_source_field()) then
        call TLS_info ('  No magnetic source field; setting the Joule heat to zero.')
        call zero_joule_power_density ()
      else
        call TLS_info ('  Computing the Joule heat ...')
        call compute_joule_heat ()
      end if

    end if

    !! Write the initial Joule heat to the xml output file.
    call danu_write_joule (t)

    call TLS_info (' Electromagnetics initialized.')

  end subroutine initialize_EM
  
  !! This auxillary routine ensures that the EM material properties are
  !! defined for every material phase.  Where necessary it assigns constant
  !! default values in keeping with legacy behavior: 0 for conductivity and
  !! the susceptibilities.  This should be called before attempting to
  !! evaluate the properties on the mesh.
  
  subroutine init_material_properties
  
    call add_property ('electrical conductivity', 0.0_rk)
    call add_property ('electric susceptibility', 0.0_rk)
    call add_property ('magnetic susceptibility', 0.0_rk)
    
  contains
  
    !! Ensure that every material phase has the specified property
    !! defined, adding it if necessary with the given default value.
    
    subroutine add_property (prop, default)
    
      use phase_property_table
      use parameter_module, only: nmat
      use material_interop, only: void_material_index, material_to_phase
      use scalar_func_factories
      
      character(*),  intent(in) :: prop
      real(kind=rk), intent(in) :: default
      
      integer :: prop_id, phase_id, m
      class(scalar_func), allocatable :: f_default
      character(128) :: message

      if (ppt_has_property(prop)) then
        prop_id = ppt_property_id(prop)
      else
        call ppt_add_property (prop, prop_id)
      end if
      
      do m = 1, nmat
        if (m == void_material_index) cycle
        phase_id = material_to_phase(m)
        ASSERT(phase_id > 0)
        if (ppt_has_phase_property (phase_id, prop_id)) cycle
        call alloc_const_scalar_func (f_default, default)
        call ppt_assign_phase_property (phase_id, prop_id, f_default)
        write(message,'(2x,3a,es10.3,3a)') 'Using default value "', trim(prop), '" =', &
            default, ' for phase "', trim(ppt_phase_name(phase_id)), '"'
        call TLS_info (message)
      end do
      
    end subroutine add_property

  end subroutine init_material_properties

 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 !!
 !! INDUCTION_HEATING
 !!
 !! Orchestrates the calculation of the time-averaged Joule heat that will be
 !! used over the time interval [t1, t2].  The result is stored in the EM data
 !! proxy for later retrieval with the access function JOULE_POWER_DENSITY.
 !!

  subroutine induction_heating (t1, t2)

    use property_module, only:  EM_permittivity, EM_permeability, EM_conductivity

    real(kind=rk), intent(in) :: t1, t2

    real(kind=rk) :: s
    character(len=10) :: ss

    if (EM_is_off()) return

    !! Push the source and EM material parameters at time T1 into the EM data proxy.
    call set_source_properties (t1)
    call set_permittivity (EM_permittivity())
    call set_permeability (EM_permeability())
    call set_conductivity (EM_conductivity())

    if (no_source_field()) then ! there is no joule heat ...
      if (source_has_changed()) then
        call TLS_info (' No magnetic source field; setting the Joule heat to zero.')
        call zero_joule_power_density ()
        call danu_write_joule (t1)
      end if
    else if (material_has_changed()) then
      call TLS_info (' EM material parameters have changed; computing the Joule heat ...')
      call compute_joule_heat ()
      call danu_write_joule (t1)
    else if (source_has_changed()) then
      if (source_is_scaled(s)) then
        write(ss,fmt='(es9.3)') s
        call TLS_info (' Magnetic source field was scaled by ' // trim(ss) // '; Joule heat scaled accordingly.')
        call scale_joule_power_density (s)
      else
        call TLS_info (' Magnetic source field has changed; computing the Joule heat ...')
        call compute_joule_heat ()
      end if
      call danu_write_joule (t1)
    end if

  end subroutine induction_heating

 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 !!
 !!  DRIVER FOR THE JOULE HEAT SIMULATION -- SERIAL CODE
 !!
  
  subroutine compute_joule_heat ()

    use simpl_mesh_type
    use mimetic_discretization
    use MaxwellEddy
    use EM_boundary_data
    use EM_graphics_output

    integer :: j, status, n, cg_max_itr, steps_per_cycle
    real(kind=rk), pointer :: eps(:), mu(:), sigma(:)
    type(simpl_mesh), pointer :: mesh

    type(system) :: sys
    real(kind=rk), pointer :: efield(:), bfield(:), q(:), q_avg(:), q_avg_last(:)
    real(kind=rk) :: t, dt, error, eps0, mu0, sigma0, escf, bscf, qscf, freq, curr, etasq, delta, cg_red
    logical :: converged
    character(len=256) :: string
    real(kind=rk) :: eps_min, eps_max, mu_min, mu_max, sigma_min, sigma_max
    
    !call TLS_info (' Beginning Joule Heat Simulation...')
    
    !! Get the mesh from the EM data proxy and create the discretization.
    mesh => EM_mesh()

    !! Initialize the boundary conditions.
    call cylinder_bv_init (mesh)

    eps   => permittivity()
    mu    => permeability()
    sigma => conductivity()
    
    if (global_any(eps <= 0.0_rk)) call TLS_fatal ('COMPUTE_JOULE_HEAT: Epsilon is not positive')
    if (global_any(mu  <= 0.0_rk)) call TLS_fatal ('COMPUTE_JOULE_HEAT: Mu is not positive')
    if (global_any(sigma <0.0_rk)) call TLS_fatal ('COMPUTE_JOULE_HEAT: Sigma is not nonnegative')
    
    eps_min = global_minval(eps)
    eps_max = global_maxval(eps)
    mu_min = global_minval(mu)
    mu_max = global_maxval(mu)
    sigma_min = global_minval(sigma, mask=(sigma > 0.0_rk))
    sigma_max = global_maxval(sigma)
    
    if (is_IOP) then
      write(string,fmt='(3x,2(a,es11.4))') 'Min epsilon=', eps_min,   ', Max epsilon=', eps_max
      call TLS_info (trim(string))
      write(string,fmt='(3x,2(a,es11.4))') 'Min mu=     ', mu_min,    ', Max mu=     ', mu_max
      call TLS_info (trim(string))
      write(string,fmt='(3x,2(a,es11.4))') 'Min sigma=  ', sigma_min, ', Max sigma=  ', sigma_max
      call TLS_info (trim(string))
    end if
    
    eps0 = get_epsilon_0()
    mu0 = get_mu_0()
    sigma0 = sigma_max
    
    if (sigma0 <= 0.0_rk) call TLS_fatal ('COMPUTE_JOULE_HEAT: Sigma is uniformly zero!')
    
    !coil => get_coil()
    freq = source_frequency()
    curr = 1.0_rk ! multiple coils, so no scaling of the current for now.
    !curr = coil%current

    etasq = eps0 * freq / sigma0
    delta = 1.0_rk / sqrt(mu0 * sigma0 * freq)
    
    if (is_IOP) then
      write(string,fmt='(3x,a,es11.4)') 'DELTA=', delta
      call TLS_info (trim(string))
      write(string,fmt='(3x,a,es11.4)') 'ETASQ=', etasq
      call TLS_info (trim(string))
    end if
    
    if (get_num_etasq() > etasq) then
      etasq = get_num_etasq()
      if (is_IOP) then
        write(string,fmt='(3x,a,es11.4)') 'Using input numerical ETASQ value instead:', etasq
        call TLS_info (trim(string))
      end if
    end if
        
    !! Scale factors: physical var = scale factor * computational var.
    bscf = mu0 * curr
    escf = curr / sigma0
    qscf = curr**2 / sigma0
    
    steps_per_cycle = get_steps_per_cycle()
    cg_red = get_cg_stopping_tolerance()
    cg_max_itr = get_maximum_cg_iterations()
    
    !! Create and initialize the time-discretized system.
    dt = 1.0_rk / real(steps_per_cycle,kind=rk)
    call initialize_system (sys, mesh, eps, mu, sigma/sigma0, etasq, delta, dt, bdata%ebedge)
    call set_param (sys, minitr=1, maxitr=cg_max_itr, tol=0.0_rk, red=cg_red)
    call set_param (sys, output_level=get_output_level())

    allocate(efield(mesh%nedge), bfield(mesh%nface))
    allocate(q(mesh%ncell), q_avg(mesh%ncell), q_avg_last(mesh%ncell))

    t = 0.0_rk
    efield = 0.0_rk
    bfield = 0.0_rk
    call set_initial_values (sys, t, efield, bfield)

    q = qscf * joule_heat(sys, efield)
    
    if (graphics()) then
      call export_mesh (mesh, eps, mu, sigma)
!NNC!      if (get_num_probe_points() > 0) then
!NNC!        allocate(probe_point(3,get_num_probe_points()))
!NNC!        probe_point = get_probe_points()
!NNC!      end if
!NNC!      call initialize_probes (mesh)
!NNC!      call update_probes (t, escf*efield, bscf*bfield, q*mesh%volume)
    end if

    converged = .false.
    
    STEADY_STATE: do n = 1, get_maximum_source_cycles()

      if (converged) exit

      if (graphics()) then
        call initialize_field_output ()
        if (n == 1) call export_fields (mesh, t, escf*efield, bscf*bfield, q)
      end if

      q_avg = 0.0_rk
      
      SOURCE_CYCLE: do j = 1, steps_per_cycle
      
        q_avg = q_avg + 0.5_rk * q
        
        call step (sys, t, efield, bfield, status, set_bv, bndry_src)
        if (global_any(status /= 0)) exit STEADY_STATE
        
        q = qscf * joule_heat(sys, efield)
        if (graphics()) then
          call export_fields (mesh, t, escf*efield, bscf*bfield, q)
!NNC!          call update_probes (t, escf*efield, bscf*bfield, q*mesh%volume)
        end if
        
        q_avg = q_avg + 0.5_rk * q
        
      end do SOURCE_CYCLE

      !! Time-averaged Joule power density over the last source cycle.
      q_avg = q_avg / real(steps_per_cycle,kind=rk)

      write(string,fmt='(t4,a,i4,2(a,es11.4))') 'Source cycle', n, &
        ': |Q|_max=', global_maxval(q_avg), ', Q_total=', &
        global_dot_product(q_avg(:mesh%ncell_onP), abs(mesh%volume(:mesh%ncell_onP)))
      call TLS_info (trim(string))

      if (graphics()) call finalize_field_output (q_avg)
      
      !! Check for 'convergence' to the steady-state periodic solution.
      if (n > 1) then
        error = global_maxval(abs(q_avg-q_avg_last)) / global_maxval(abs(q_avg))
        converged = (error < get_ss_stopping_tolerance())
      end if

      q_avg_last = q_avg

    end do STEADY_STATE

    !! Check for time step failure.
    if (global_any(status /= 0)) then ! finalize the output and bail.
      if (graphics()) then
!NNC!        call write_probes (em_output)
      end if
      call TLS_fatal ('COMPUTE_JOULE_HEAT: EM time step failure')
    end if

    if (graphics()) then
!NNC!      call write_probes (em_output)
    end if
    
    !! Store the the computed Joule heat in the EM data proxy for later retrieval.
    call set_joule_power_density (q_avg)

    !! Check for convergence to steady state.  We continue in any case.
    if (.not.converged) then
      call TLS_warn ('COMPUTE_JOULE_HEAT: Not converged to steady-state; proceding anyway.')
    end if

    !! Clean-up.
    deallocate(efield, bfield, q, q_avg, q_avg_last)
    call destroy_system (sys)
    ! The BDATA structure needs to be deallocated too!

    call TLS_info ('  Joule heat computation completed.')
    
  end subroutine compute_joule_heat

end module EM
