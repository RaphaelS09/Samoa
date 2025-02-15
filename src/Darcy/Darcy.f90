! Sam(oa)² - SFCs and Adaptive Meshes for Oceanic And Other Applications
! Copyright (C) 2010 Oliver Meister, Kaveh Rahnema
! This program is licensed under the GPL, for details see the file LICENSE


#include "Compilation_control.f90"

#if defined(_DARCY)
	MODULE Darcy
		use Darcy_data_types
		use Darcy_initialize_pressure
		use Darcy_initialize_saturation
		use Darcy_vtk_output
		use Darcy_xml_output
		use Darcy_lse_output
		use Darcy_grad_p
		use Darcy_pressure_solver_jacobi
		use Darcy_pressure_solver_cg
		use Darcy_pressure_solver_pipecg
		use Darcy_pressure_solver_pipecg_unst
		use Darcy_transport_eq
		use Darcy_permeability
		use Darcy_error_estimate
		use Darcy_adapt

		use linear_solver

		use Samoa_darcy

		implicit none

		type t_darcy
            type(t_darcy_init_pressure_traversal)           :: init_pressure
            type(t_darcy_init_saturation_traversal)         :: init_saturation
            type(t_darcy_vtk_output_traversal)              :: vtk_output
            type(t_darcy_xml_output_traversal)              :: xml_output
            type(t_darcy_lse_output_traversal)              :: lse_output
            type(t_darcy_grad_p_traversal)                  :: grad_p
            type(t_darcy_transport_eq_traversal)            :: transport_eq
            type(t_darcy_permeability_traversal)            :: permeability
            type(t_darcy_error_estimate_traversal)          :: error_estimate
            type(t_darcy_adaption_traversal)                :: adaption
            class(t_linear_solver), pointer                 :: pressure_solver

            contains

            procedure , pass :: create => darcy_create
            procedure , pass :: run => darcy_run
            procedure , pass :: destroy => darcy_destroy
        end type

		private
		public t_darcy

		contains

		!> Creates all required runtime objects for the scenario
		subroutine darcy_create(darcy, grid, l_log, i_asagi_mode)
            class(t_darcy)                                              :: darcy
 			type(t_grid), intent(inout)									:: grid
			logical, intent(in)						                    :: l_log
			integer, intent(in)											:: i_asagi_mode

			!local variables
			character (len = 64)										:: s_log_name, s_date, s_time
			integer                                                     :: i_error
            type(t_darcy_pressure_solver_jacobi)                        :: pressure_solver_jacobi
            type(t_darcy_pressure_solver_cg)                            :: pressure_solver_cg
            type(t_darcy_pressure_solver_pipecg)                        :: pressure_solver_pipecg
            type(t_darcy_pressure_solver_pipecg_unst)                   :: pressure_solver_pipecg_unst

            !allocate solver

 			grid%r_time = 0.0_GRID_SR

            call darcy%init_pressure%create()
            call darcy%init_saturation%create()
            call darcy%vtk_output%create()
            call darcy%xml_output%create()
            call darcy%lse_output%create()
            call darcy%grad_p%create()
            call darcy%transport_eq%create()
            call darcy%permeability%create()
            call darcy%error_estimate%create()
            call darcy%adaption%create()

 			select case (cfg%i_lsolver)
                case (0)
                    call pressure_solver_jacobi%create(real(cfg%r_epsilon * cfg%r_p0, GRID_SR))
                    allocate(darcy%pressure_solver, source=pressure_solver_jacobi, stat=i_error); assert_eq(i_error, 0)
                case (1)
                    call pressure_solver_cg%create(real(cfg%r_epsilon * cfg%r_p0, GRID_SR), cfg%i_CG_restart)
                    allocate(darcy%pressure_solver, source=pressure_solver_cg, stat=i_error); assert_eq(i_error, 0)
                case (2)
                    call pressure_solver_pipecg%create(real(cfg%r_epsilon * cfg%r_p0, GRID_SR), cfg%i_CG_restart)
                    allocate(darcy%pressure_solver, source=pressure_solver_pipecg, stat=i_error); assert_eq(i_error, 0)
                case (3)
                    call pressure_solver_pipecg_unst%create(real(cfg%r_epsilon * cfg%r_p0, GRID_SR), cfg%i_CG_restart)
                    allocate(darcy%pressure_solver, source=pressure_solver_pipecg_unst, stat=i_error); assert_eq(i_error, 0)
                case default
                    try(.false., "Invalid linear solver, must be in range 0 to 3")
            end select

			call date_and_time(s_date, s_time)

#           if defined(_MPI)
                call mpi_bcast(s_date, len(s_date), MPI_CHARACTER, 0, MPI_COMM_WORLD, i_error); assert_eq(i_error, 0)
                call mpi_bcast(s_time, len(s_time), MPI_CHARACTER, 0, MPI_COMM_WORLD, i_error); assert_eq(i_error, 0)
#           endif

			write (darcy%vtk_output%s_file_stamp, "(A, A, A8, A, A6)") "output/darcy", "_", s_date, "_", s_time
			write (darcy%xml_output%s_file_stamp, "(A, A, A8, A, A6)") "output/darcy", "_", s_date, "_", s_time

			write (s_log_name, '(A, A)') TRIM(darcy%vtk_output%s_file_stamp), ".log"

			if (l_log) then
				_log_open_file(s_log_name)
			endif

			call load_permeability(grid, cfg%s_permeability_file)
		end subroutine

		subroutine load_permeability(grid, s_template)
			type(t_grid), target, intent(inout)		:: grid
			character(256)					        :: s_template

            integer                                 :: i_asagi_hints
			integer									:: i_error, i, j, i_ext_pos
			character(256)					        :: s_file_name

#			if defined(_ASAGI)
                !convert ASAGI mode to ASAGI hints

                select case(cfg%i_asagi_mode)
                    case (0)
                        i_asagi_hints = GRID_NO_HINT
                    case (1)
                        i_asagi_hints = ieor(GRID_NOMPI, GRID_PASSTHROUGH)
                    case (2)
                        i_asagi_hints = GRID_NOMPI
                    case (3)
                        i_asagi_hints = ieor(GRID_NOMPI, SMALL_CACHE)
                    case (4)
                        i_asagi_hints = GRID_LARGE_GRID
                    case default
                        try(.false., "Invalid asagi mode, must be in range 0 to 4")
                end select

#               if defined(_ASAGI_NUMA)
                    cfg%afh_permeability = grid_create_for_numa(grid_type = GRID_FLOAT, hint = i_asagi_hints, levels = 1, tcount=omp_get_max_threads())

					!$omp parallel private(i_error, i, j, i_ext_pos, s_file_name)
						i_error = grid_register_thread(cfg%afh_permeability); assert_eq(i_error, GRID_SUCCESS)

						do j = min(10, cfg%i_max_depth / 2), 0, -1
                            i_ext_pos = index(s_template, ".", .true.)
                            write (s_file_name, fmt = '(A, "_", I0, A)') s_template(: i_ext_pos - 1), 2 ** j, trim(s_template(i_ext_pos :))

                            i_error = asagi_open(cfg%afh_permeability, trim(s_file_name), 0)

                            if (i_error == GRID_SUCCESS) then
                                exit
                            endif
                        end do

	                    assert_eq(i_error, GRID_SUCCESS)

	                    if (rank_MPI == 0) then
	                		associate(afh => cfg%afh_permeability)
	                        	_log_write(1, '(" Darcy: loaded ", A, ", domain: [", F0.2, ", ", F0.2, "] x [", F0.2, ", ", F0.2, "], time: [", F0.2, ", ", F0.2, "]")') &
	                        	    trim(s_file_name), grid_min_x(afh), grid_max_x(afh),  grid_min_y(afh), grid_max_y(afh),  grid_min_z(afh), grid_max_z(afh)
	                		end associate
	                    end if
					!$omp end parallel
#               else
                    cfg%afh_permeability = asagi_create(grid_type = GRID_FLOAT, hint = i_asagi_hints, levels = cfg%i_max_depth / 2 + 1)

                    do i = 0, cfg%i_max_depth / 2
                        do j = i, 0, -1
                            i_ext_pos = index(s_template, ".", .true.)
                            write (s_file_name, fmt = '(A, "_", I0, A)') s_template(: i_ext_pos - 1), 2 ** j, trim(s_template(i_ext_pos :))

                            i_error = asagi_open(cfg%afh_permeability, trim(s_file_name), i)

                            if (i_error == GRID_SUCCESS) then
                                exit
                            endif
                        end do

                        assert_eq(i_error, GRID_SUCCESS)

                        if (rank_MPI == 0) then
                    		associate(afh => cfg%afh_permeability)
                            	_log_write(1, '(" Darcy: loaded ", A, ", domain: [", F0.2, ", ", F0.2, "] x [", F0.2, ", ", F0.2, "], time: [", F0.2, ", ", F0.2, "]")') &
                            	    trim(s_file_name), grid_min_x(afh), grid_max_x(afh),  grid_min_y(afh), grid_max_y(afh),  grid_min_z(afh), grid_max_z(afh)
                    		end associate
                        end if
                    end do
#               endif
#			endif

            cfg%scaling = 1.0_GRID_SR
            cfg%offset = [0.0_GRID_SR, 0.0_GRID_SR]
		end subroutine

		!> Destroys all required runtime objects for the scenario
		subroutine darcy_destroy(darcy, grid, l_log)
            class(t_darcy)                  :: darcy
 			type(t_grid), intent(inout)     :: grid
            integer                         :: i_error
            logical		                    :: l_log

            call darcy%init_pressure%destroy()
            call darcy%init_saturation%destroy()
            call darcy%vtk_output%destroy()
            call darcy%xml_output%destroy()
            call darcy%lse_output%destroy()
            call darcy%grad_p%destroy()
            call darcy%transport_eq%destroy()
            call darcy%error_estimate%destroy()
            call darcy%permeability%destroy()
            call darcy%adaption%destroy()

            if (associated(darcy%pressure_solver)) then
                call darcy%pressure_solver%destroy()

                deallocate(darcy%pressure_solver, stat = i_error); assert_eq(i_error, 0)
            end if

			if (l_log) then
				_log_close_file()
			endif

#			if defined(_ASAGI)
				call asagi_close(cfg%afh_permeability)
#			endif
		end subroutine

		!> Sets the initial values of the scenario and runs the time steps
		subroutine darcy_run(darcy, grid)
            class(t_darcy), intent(inout)	                            :: darcy
 			type(t_grid), intent(inout)									:: grid

            integer (kind = GRID_SI)									:: i_initial_step, i_time_step, i_lse_iterations
			real (kind = GRID_SR)										:: r_time_next_output
			type(t_grid_info)           	                            :: grid_info, grid_info_max
            integer  (kind = GRID_SI)                                   :: i_stats_phase

			!init parameters
			r_time_next_output = 0.0_GRID_SR

            if (rank_MPI == 0) then
                !$omp master
                _log_write(0, *) "Darcy: setting initial values and solving initial system.."
                _log_write(0, *) ""
                !$omp end master
            end if

            call update_stats(darcy, grid)
			i_stats_phase = 0

            i_initial_step = 0

			!set pressure initial condition
			call darcy%init_pressure%traverse(grid)

			do
				!reset saturation to initial condition, compute permeability and set refinement flag
				call darcy%init_saturation%traverse(grid)

                if (cfg%l_lse_output) then
                    call darcy%lse_output%traverse(grid)
                end if

				!solve pressure equation
				i_lse_iterations = darcy%pressure_solver%solve(grid)

                if (cfg%l_lse_output) then
                    call darcy%lse_output%traverse(grid)
                end if

                if (rank_MPI == 0) then
                    grid_info%i_cells = grid%get_cells(MPI_SUM, .false.)

                    !$omp master
                    _log_write(1, "(A, I0, A, I0, A, I0, A)") " Darcy: ", i_initial_step, " adaptions, ", i_lse_iterations, " iterations, ", grid_info%i_cells, " cells"
                    !$omp end master
                end if

                grid_info%i_cells = grid%get_cells(MPI_SUM, .true.)
				if (darcy%init_saturation%i_refinements_issued .le. grid_info%i_cells / 100_GRID_DI) then
					exit
				endif

				!refine grid
				call darcy%adaption%traverse(grid)

				i_initial_step = i_initial_step + 1
			end do

            grid_info = grid%get_info(MPI_SUM, .true.)

            if (rank_MPI == 0) then
                !$omp master
                _log_write(0, *) "Darcy: done."
                _log_write(0, *) ""

                call grid_info%print()
                !$omp end master
            end if

			!output initial grid
			if (cfg%r_output_time_step >= 0.0_GRID_SR) then
				call darcy%grad_p%traverse(grid)
                call darcy%permeability%traverse(grid)
				call darcy%xml_output%traverse(grid)
				r_time_next_output = r_time_next_output + cfg%r_output_time_step
			end if

			!print initial stats
			if (cfg%i_stats_phases >= 0) then
                call update_stats(darcy, grid)

                i_stats_phase = i_stats_phase + 1
			end if

            i_time_step = 0

			do
				if ((cfg%r_max_time >= 0.0 .and. grid%r_time > cfg%r_max_time) .or. (cfg%i_max_time_steps >= 0 .and. i_time_step >= cfg%i_max_time_steps)) then
					exit
				end if

				!refine grid if necessary
				!if (darcy%permeability%i_refinements_issued > 0) then
					!refine grid
					call darcy%adaption%traverse(grid)

					!recompute permeability + refinement flag
					call darcy%permeability%traverse(grid)
				!end if

                if (cfg%l_lse_output) then
                    call darcy%lse_output%traverse(grid)
                end if

				!solve pressure equation
				i_lse_iterations = darcy%pressure_solver%solve(grid)

                if (cfg%l_lse_output) then
                    call darcy%lse_output%traverse(grid)
                end if

				!compute velocity field
				call darcy%grad_p%traverse(grid)

				!transport equation time step
				call darcy%transport_eq%traverse(grid)
				i_time_step = i_time_step + 1

				!compute permeability field + refinement flag
				call darcy%error_estimate%traverse(grid)

                if (rank_MPI == 0) then
                    grid_info%i_cells = grid%get_cells(MPI_SUM, .false.)

                    !$omp master
                    _log_write(1, '(A, I0, A, ES14.7, A, ES14.7, A, I0, A, I0)') " Darcy: time step: ", i_time_step, ", sim. time:", grid%r_time, " s, dt:", grid%r_dt, " s, cells: ", grid_info%i_cells, ", LSE iterations: ", i_lse_iterations
                    !$omp end master
                end if

				!output grid
				if (cfg%r_output_time_step >= 0.0_GRID_SR .and. grid%r_time >= r_time_next_output) then
                    call darcy%permeability%traverse(grid)
					call darcy%xml_output%traverse(grid)
					r_time_next_output = r_time_next_output + cfg%r_output_time_step
				end if

                !print stats
                if ((cfg%r_max_time >= 0.0d0 .and. grid%r_time * cfg%i_stats_phases >= i_stats_phase * cfg%r_max_time) .or. &
                    (cfg%i_max_time_steps >= 0 .and. i_time_step * cfg%i_stats_phases >= i_stats_phase * cfg%i_max_time_steps)) then
                    call update_stats(darcy, grid)

                    i_stats_phase = i_stats_phase + 1
                end if
			end do

            grid_info = grid%get_info(MPI_SUM, .true.)
            grid_info_max = grid%get_info(MPI_MAX, .true.)

            !$omp master
            if (rank_MPI == 0) then
                _log_write(0, '(" Darcy: done.")')
                _log_write(0, '()')
                _log_write(0, '("  Cells: avg: ", I0, " max: ", I0)') grid_info%i_cells / (omp_get_max_threads() * size_MPI), grid_info_max%i_cells
                _log_write(0, '()')

                call grid_info%print()
            end if
            !$omp end master
		end subroutine

		subroutine update_stats(darcy, grid)
            class(t_darcy), intent(inout)   :: darcy
 			type(t_grid), intent(inout)     :: grid

 			double precision, save          :: t_phase = huge(1.0d0)

			!$omp master
                !Initially, just start the timer and don't print anything
                if (t_phase < huge(1.0d0)) then
                    t_phase = t_phase + get_wtime()

                    call darcy%init_saturation%reduce_stats(MPI_SUM, .true.)
                    call darcy%transport_eq%reduce_stats(MPI_SUM, .true.)
                    call darcy%grad_p%reduce_stats(MPI_SUM, .true.)
                    call darcy%permeability%reduce_stats(MPI_SUM, .true.)
                    call darcy%error_estimate%reduce_stats(MPI_SUM, .true.)
                    call darcy%adaption%reduce_stats(MPI_SUM, .true.)
                    call darcy%pressure_solver%reduce_stats(MPI_SUM, .true.)
                    call grid%reduce_stats(MPI_SUM, .true.)

                    if (rank_MPI == 0) then
                        _log_write(0, *) ""
                        _log_write(0, *) "Phase statistics:"
                        _log_write(0, *) ""
                        _log_write(0, '(A, T34, A)') " Init: ", trim(darcy%init_saturation%stats%to_string())
                        _log_write(0, '(A, T34, A)') " Transport: ", trim(darcy%transport_eq%stats%to_string())
                        _log_write(0, '(A, T34, A)') " Gradient: ", trim(darcy%grad_p%stats%to_string())
                        _log_write(0, '(A, T34, A)') " Permeability: ", trim(darcy%permeability%stats%to_string())
                        _log_write(0, '(A, T34, A)') " Error Estimate: ", trim(darcy%error_estimate%stats%to_string())
                        _log_write(0, '(A, T34, A)') " Adaptions: ", trim(darcy%adaption%stats%to_string())
                        _log_write(0, '(A, T34, A)') " Pressure Solver: ", trim(darcy%pressure_solver%stats%to_string())
                        _log_write(0, '(A, T34, A)') " Grid: ", trim(grid%stats%to_string())
                        _log_write(0, '(A, T34, F12.4, A)') " Element throughput: ", 1.0d-6 * dble(grid%stats%i_traversed_cells) / t_phase, " M/s"
                        _log_write(0, '(A, T34, F12.4, A)') " Memory throughput: ", dble(grid%stats%i_traversed_memory) / ((1024 * 1024 * 1024) * t_phase), " GB/s"
                        _log_write(0, '(A, T34, F12.4, A)') " Asagi time:", grid%stats%r_asagi_time, " s"
                        _log_write(0, '(A, T34, F12.4, A)') " Phase time:", t_phase, " s"
                        _log_write(0, *) ""
                    end if
                end if

                call darcy%init_saturation%clear_stats()
                call darcy%transport_eq%clear_stats()
                call darcy%grad_p%clear_stats()
                call darcy%permeability%clear_stats()
                call darcy%error_estimate%clear_stats()
                call darcy%adaption%clear_stats()
                call darcy%pressure_solver%clear_stats()
                call grid%clear_stats()

                t_phase = -get_wtime()
            !$omp end master
        end subroutine
	END MODULE Darcy
#endif
