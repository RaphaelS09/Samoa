! Sam(oa)² - SFCs and Adaptive Meshes for Oceanic And Other Applications
! Copyright (C) 2010 Oliver Meister, Kaveh Rahnema
! This program is licensed under the GPL, for details see the file LICENSE

#include "Compilation_control.f90"

#define _CG							            _solver
#define _CG_USE								    _solver_use

#define _PREFIX3(P, X)							_conc3(P,_,X)
#define _T_CG								    _PREFIX3(t,_CG)
#define _CG_(X)									_PREFIX3(_CG,X)
#define _T_CG_(X)								_PREFIX3(t,_CG_(X))

#define _gv_size								(3 * _gv_node_size + 3 * _gv_edge_size + _gv_cell_size)

MODULE _CG_(step)
    use SFC_edge_traversal
    use _CG_USE

    implicit none

    type num_traversal_data
        real (kind = GRID_SR)					:: alpha					!< step size
        real (kind = GRID_SR)				    :: beta						!< update ratio
        real (kind = GRID_SR)				    :: d_u					    !< d^T * u
        real (kind = GRID_SR)				    :: v_u					    !< v^T * u
        real (kind = GRID_SR)				    :: r_C_r					!< r^T * C * r
        real (kind = GRID_SR)					:: r_sq						!< r^2

#       if !defined(_solver_unstable)
            real (kind = GRID_SR)				:: r_u					    !< r^T * u
#       endif
    end type

    !LSE variables
    type(_gm_A)				        :: gm_A                 !< temporary/persistent matrix
    type(_gv_x)						:: gv_x                 !< persistent solution

    !if no rhs is defined, we assume rhs = 0
#   if defined(_gv_rhs)
        type(_gv_rhs)			    :: gv_rhs
#   endif

    !solver-specific variables
    type(_gv_r)						:: gv_r                 !< persistent residual
    type(_gv_trace_A)			    :: gv_trace_A           !< temporary/persistent trace of matrix
    type(_gv_d)						:: gv_d                 !< persistent solution update
    type(_gv_v)					    :: gv_v                 !< persistent residual update

    !if no Dirichlet boundaries are defined, we assume Neumann boundaries everywhere
#   if defined(_gv_dirichlet)
        type(_gv_dirichlet)		    :: gv_dirichlet         !< persistent boundary indicator
#   endif

#		define _GT_NAME							_T_CG_(step_traversal)

#		if (_gv_edge_size > 0)
#			define _GT_EDGES
#		endif

#		if (_gv_node_size > 0)
#		    define _GT_NODES
#		endif

#		define _GT_NO_COORDS

#		define _GT_PRE_TRAVERSAL_GRID_OP		pre_traversal_grid_op
#		define _GT_POST_TRAVERSAL_GRID_OP		post_traversal_grid_op
#		define _GT_PRE_TRAVERSAL_OP				pre_traversal_op

#		define _GT_ELEMENT_OP					element_op

#		define _GT_NODE_FIRST_TOUCH_OP			node_first_touch_op
#		define _GT_NODE_LAST_TOUCH_OP			node_last_touch_op
#		define _GT_NODE_REDUCE_OP			    node_reduce_op
#		define _GT_INNER_NODE_LAST_TOUCH_OP		inner_node_last_touch_op
#		define _GT_INNER_NODE_REDUCE_OP		    inner_node_reduce_op

#		define _GT_NODE_MERGE_OP		        node_merge_op
#		define _GT_NODE_WRITE_OP		        node_write_op

!#		define _GT_NODE_MPI_TYPE
#		define _GT_EDGE_MPI_TYPE

#		include "SFC_generic_traversal_ringbuffer.f90"

    subroutine create_node_mpi_type(mpi_node_type)
        integer, intent(out)    :: mpi_node_type

        type(t_node_data)               :: node
        integer                         :: blocklengths(4), types(4), disps(4), i_error, extent

#       if defined(_MPI)
            blocklengths(1) = 1
            blocklengths(2) = 1
            blocklengths(3) = 1
            blocklengths(4) = 1

            disps(1) = 0
            disps(2) = loc(node%data_pers%A_d) - loc(node)
            disps(3) = loc(node%data_temp%mat_diagonal) - loc(node)
            disps(4) = sizeof(node)

            types(1) = MPI_LB
            types(2) = MPI_DOUBLE_PRECISION
            types(3) = MPI_DOUBLE_PRECISION
            types(4) = MPI_UB

            call MPI_Type_struct(4, blocklengths, disps, types, mpi_node_type, i_error); assert_eq(i_error, 0)
            call MPI_Type_commit(mpi_node_type, i_error); assert_eq(i_error, 0)

            call MPI_Type_extent(mpi_node_type, extent, i_error); assert_eq(i_error, 0)
            assert_eq(sizeof(node), extent)

            call MPI_Type_size(mpi_node_type, extent, i_error); assert_eq(i_error, 0)
            assert_eq(16, extent)
#       endif
    end subroutine

    subroutine create_edge_mpi_type(mpi_edge_type)
        integer, intent(out)            :: mpi_edge_type

        type(t_edge_data)               :: edge
        integer                         :: blocklengths(2), types(2), disps(2), i_error, extent

#       if defined(_MPI)
            blocklengths(1) = 1
            blocklengths(2) = 1

            disps(1) = 0
            disps(2) = sizeof(edge)

            types(1) = MPI_LB
            types(2) = MPI_UB

            call MPI_Type_struct(2, blocklengths, disps, types, mpi_edge_type, i_error); assert_eq(i_error, 0)
            call MPI_Type_commit(mpi_edge_type, i_error); assert_eq(i_error, 0)

            call MPI_Type_extent(mpi_edge_type, extent, i_error); assert_eq(i_error, 0)
            assert_eq(sizeof(edge), extent)

            call MPI_Type_size(mpi_edge_type, extent, i_error); assert_eq(i_error, 0)
            assert_eq(0, extent)
#       endif
    end subroutine

    subroutine pre_traversal_grid_op(traversal, grid)
        type(_T_CG_(step_traversal)), intent(inout)					:: traversal
        type(t_grid), intent(inout)							        :: grid

        call scatter(traversal%alpha, traversal%children%alpha)
        call scatter(traversal%beta, traversal%children%beta)
    end subroutine

    subroutine post_traversal_grid_op(traversal, grid)
        type(_T_CG_(step_traversal)), intent(inout)					:: traversal
        type(t_grid), intent(inout)							        :: grid

        integer                                                     :: i_error

#       if !defined(_solver_unstable)
            real (kind = GRID_SR)                                   :: reduction_set(5)
#       else
            real (kind = GRID_SR)                                   :: reduction_set(4)
#       endif

        call reduce(traversal%d_u, traversal%children%d_u, MPI_SUM, .false.)
        call reduce(traversal%v_u, traversal%children%v_u, MPI_SUM, .false.)
        call reduce(traversal%r_C_r, traversal%children%r_C_r, MPI_SUM, .false.)
        call reduce(traversal%r_sq, traversal%children%r_sq, MPI_SUM, .false.)

        reduction_set(1) = traversal%d_u
        reduction_set(2) = traversal%v_u
        reduction_set(3) = traversal%r_C_r
        reduction_set(4) = traversal%r_sq

#       if !defined(_solver_unstable)
            call reduce(traversal%r_u, traversal%children%r_u, MPI_SUM, .false.)

            reduction_set(5) = traversal%r_u

            call reduce(reduction_set, MPI_SUM)

            traversal%r_u = reduction_set(5)
#       else
            call reduce(reduction_set, MPI_SUM)
#       endif

        traversal%d_u = reduction_set(1)
        traversal%v_u = reduction_set(2)
        traversal%r_C_r = reduction_set(3)
        traversal%r_sq = reduction_set(4)
    end subroutine

    pure subroutine pre_traversal_op(traversal, section)
        type(_T_CG_(step_traversal)), intent(inout)	    :: traversal
        type(t_grid_section), intent(inout)			    :: section

        traversal%d_u = 0.0_GRID_SR
        traversal%v_u = 0.0_GRID_SR
        traversal%r_C_r = 0.0_GRID_SR
        traversal%r_sq = 0.0_GRID_SR

#       if !defined(_solver_unstable)
            traversal%r_u = 0.0_GRID_SR
#       endif
    end subroutine

    !*******************************
    !Geometry operators
    !*******************************

    elemental subroutine node_first_touch_op(traversal, section, node)
        type(_T_CG_(step_traversal)), intent(in)    :: traversal
        type(t_grid_section), intent(in)		    :: section
        type(t_node_data), intent(inout)			:: node


        real(kind = GRID_SR)                        :: x(_gv_node_size)
        real(kind = GRID_SR)                        :: r(_gv_node_size)
        real(kind = GRID_SR)                        :: d(_gv_node_size)
        real(kind = GRID_SR)                        :: v(_gv_node_size)
        real(kind = GRID_SR)                        :: trace_A(_gv_node_size)

#       if defined(_DARCY)
            !HACK: unfortunately the optimizer produces wrong code if some variables are managed by the grid variable classes,
            !so we have to use direct access here

            call pre_dof_op(traversal%alpha, traversal%beta, node%data_pers%p, node%data_pers%r, node%data_pers%d, node%data_pers%A_d, node%data_temp%mat_diagonal)
#       else
            call gv_x%read(node, x)
            call gv_r%read(node, r)
            call gv_d%read(node, d)
            call gv_v%read(node, v)

            call pre_dof_op(traversal%alpha, traversal%beta, x, r, d, v, trace_A)

            call gv_x%write(node, x)
            call gv_r%write(node, r)
            call gv_d%write(node, d)
            call gv_v%write(node, v)
            call gv_trace_A%write(node, trace_A)
#       endif
    end subroutine

    pure subroutine element_op(traversal, section, element)
        type(_T_CG_(step_traversal)), intent(in)							:: traversal
        type(t_grid_section), intent(in)							:: section
        type(t_element_base), intent(inout), target		:: element

        !local variables

        real(kind = GRID_SR)	    :: A(_gv_size, _gv_size)
        real(kind = GRID_SR)		:: d(_gv_size)
        real(kind = GRID_SR)		:: v(_gv_size)
        real(kind = GRID_SR)	    :: trace_A(_gv_size)
        integer :: i

        call gm_A%read(element, A)
        call gv_d%read(element, d)

        v = matmul(A, d)

        !add up matrix diagonal
        forall (i = 1 : _gv_size)
            trace_A(i) = A(i, i)
        end forall

        call gv_v%add(element, v)
        call gv_trace_A%add(element, trace_A)
    end subroutine

    elemental subroutine node_last_touch_op(traversal, section, node)
        type(_T_CG_(step_traversal)), intent(in)							:: traversal
        type(t_grid_section), intent(in)					:: section
        type(t_node_data), intent(inout)			:: node

        logical :: is_dirichlet(1)

        call gv_dirichlet%read(node, is_dirichlet)

        if (.not. any(is_dirichlet)) then
            call inner_node_last_touch_op(traversal, section, node)
        end if
    end subroutine

    elemental subroutine inner_node_last_touch_op(traversal, section, node)
        type(_T_CG_(step_traversal)), intent(in)							:: traversal
        type(t_grid_section), intent(in)							:: section
        type(t_node_data), intent(inout)			                :: node

        real(kind = GRID_SR)    :: v(_gv_node_size)
        real(kind = GRID_SR)    :: trace_A(_gv_node_size)

        call gv_v%read(node, v)
        call gv_trace_A%read(node, trace_A)

        call post_dof_op(v, trace_A)

        call gv_v%write(node, v)
    end subroutine

    pure subroutine node_reduce_op(traversal, section, node)
        type(_T_CG_(step_traversal)), intent(inout)		    :: traversal
        type(t_grid_section), intent(in)			    :: section
        type(t_node_data), intent(in)				    :: node

        logical :: is_dirichlet(1)

        call gv_dirichlet%read(node, is_dirichlet)

        if (.not. any(is_dirichlet)) then
            call inner_node_reduce_op(traversal, section, node)
        end if
    end subroutine

    pure subroutine inner_node_reduce_op(traversal, section, node)
        type(_T_CG_(step_traversal)), intent(inout)		    :: traversal
        type(t_grid_section), intent(in)			    :: section
        type(t_node_data), intent(in)				    :: node

        real(kind = GRID_SR)                            :: r(_gv_node_size), d(_gv_node_size)
        real(kind = GRID_SR)                            :: v(_gv_node_size), trace_A(_gv_node_size)
        integer											:: i

        call gv_r%read(node, r)
        call gv_d%read(node, d)
        call gv_v%read(node, v)
        call gv_trace_A%read(node, trace_A)

        do i = 1, _gv_node_size
#           if !defined(_solver_unstable)
                call reduce_dof_op(traversal%d_u, traversal%r_u, traversal%v_u, traversal%r_C_r, traversal%r_sq, r(i), d(i), v(i), trace_A(i))
#           else
                call reduce_dof_op(traversal%d_u, traversal%d_u, traversal%v_u, traversal%r_C_r, traversal%r_sq, r(i), d(i), v(i), trace_A(i))
#           endif
        end do
    end subroutine

    pure subroutine node_merge_op(local_node, neighbor_node)
        type(t_node_data), intent(inout)			    :: local_node
        type(t_node_data), intent(in)				    :: neighbor_node

        real(kind = GRID_SR)                            :: v(_gv_node_size)
        real(kind = GRID_SR)                            :: trace_A(_gv_node_size)

        call gv_v%read(neighbor_node, v)
        call gv_v%add(local_node, v)

        call gv_trace_A%read(neighbor_node, trace_A)
        call gv_trace_A%add(local_node, trace_A)
    end subroutine

    pure subroutine node_write_op(local_node, neighbor_node)
        type(t_node_data), intent(inout)			    :: local_node
        type(t_node_data), intent(in)				    :: neighbor_node

        real(kind = GRID_SR)                            :: v(_gv_node_size)
        real(kind = GRID_SR)                            :: trace_A(_gv_node_size)

        assert_pure(neighbor_node%data_temp%mat_diagonal(1) .ge. local_node%data_temp%mat_diagonal(1))

        call gv_v%read(neighbor_node, v)
        call gv_v%write(local_node, v)

        call gv_trace_A%read(neighbor_node, trace_A)
        call gv_trace_A%write(local_node, trace_A)
    end subroutine

    !*******************************
    !Volume and DoF operators
    !*******************************

    elemental subroutine pre_dof_op(alpha, beta, x, r, d, v, trace_A)
        real (kind = GRID_SR), intent(in)			:: alpha
        real (kind = GRID_SR), intent(in)			:: beta
        real (kind = GRID_SR), intent(inout)		    :: x
        real (kind = GRID_SR), intent(inout)	    :: r
        real (kind = GRID_SR), intent(inout)	    :: d
        real (kind = GRID_SR), intent(inout)	    :: v
        real (kind = GRID_SR), intent(out)			:: trace_A

        x = x + alpha * d
        r = r - alpha * v
        d = r + beta * d
        v = 0.0_GRID_SR
        trace_A = tiny(1.0_GRID_SR)
    end subroutine

    elemental subroutine post_dof_op(v, trace_A)
        real (kind = GRID_SR), intent(inout)		:: v
        real (kind = GRID_SR), intent(in)			:: trace_A

        v = v / trace_A
    end subroutine

    elemental subroutine reduce_dof_op(d_u, r_u, v_u, r_C_r, r_sq, r, d, v, trace_A)
        real (kind = GRID_SR), intent(inout)		:: d_u
        real (kind = GRID_SR), intent(inout)		:: r_u
        real (kind = GRID_SR), intent(inout)		:: v_u
        real (kind = GRID_SR), intent(inout)		:: r_C_r
        real (kind = GRID_SR), intent(inout)		:: r_sq
        real (kind = GRID_SR), intent(in)		    :: r
        real (kind = GRID_SR), intent(in)		    :: d
        real (kind = GRID_SR), intent(in)		    :: v
        real (kind = GRID_SR), intent(in)			:: trace_A

        d_u = d_u + (d * v * trace_A)
        v_u = v_u + (v * v * trace_A)
        r_C_r = r_C_r + (r * r * trace_A)
        r_sq = r_sq + (r * r)

#       if !defined(_solver_unstable)
            r_u = r_u + (r * v * trace_A)
#       endif
    end subroutine
END MODULE

MODULE _CG_(exact)
    use SFC_edge_traversal
    use _CG_USE

    implicit none

    type num_traversal_data
        real (kind = GRID_SR)	    :: r_C_r					!< r^T * C * r
        real (kind = GRID_SR)	    :: r_sq						!< r^2
    end type

    !LSE variables
    type(_gm_A)				        :: gm_A
    type(_gv_x)						:: gv_x

    !solver-specific persistent variables
    type(_gv_r)						:: gv_r
    type(_gv_trace_A)			    :: gv_trace_A

    !if no rhs is defined, we assume rhs = 0
#   if defined(_gv_rhs)
        type(_gv_rhs)			    :: gv_rhs
#   endif

    !if no Dirichlet boundaries are defined, we assume Neumann boundaries everywhere
#   if defined(_gv_dirichlet)
        type(_gv_dirichlet)		    :: gv_dirichlet
#   endif

#		define _GT_NAME							_T_CG_(exact_traversal)

#		if (_gv_edge_size > 0)
#			define _GT_EDGES
#		endif

#		if (_gv_node_size > 0)
#		    define _GT_NODES
#		endif

#		define _GT_NODES
#		define _GT_NO_COORDS

#		define _GT_PRE_TRAVERSAL_GRID_OP		pre_traversal_grid_op
#		define _GT_POST_TRAVERSAL_GRID_OP		post_traversal_grid_op
#		define _GT_PRE_TRAVERSAL_OP				pre_traversal_op

#		define _GT_ELEMENT_OP					element_op

#		define _GT_NODE_FIRST_TOUCH_OP			node_first_touch_op
#		define _GT_NODE_LAST_TOUCH_OP			node_last_touch_op
#		define _GT_NODE_REDUCE_OP			    node_reduce_op
#		define _GT_INNER_NODE_LAST_TOUCH_OP		inner_node_last_touch_op
#		define _GT_INNER_NODE_REDUCE_OP		    inner_node_reduce_op

#		define _GT_NODE_MERGE_OP		        node_merge_op
#		define _GT_NODE_WRITE_OP		        node_write_op

!#		define _GT_NODE_MPI_TYPE
#		define _GT_EDGE_MPI_TYPE

#		include "SFC_generic_traversal_ringbuffer.f90"

    subroutine create_node_mpi_type(mpi_node_type)
        integer, intent(out)            :: mpi_node_type

        type(t_node_data)               :: node
        integer                         :: blocklengths(4), types(4), disps(4), i_error, extent

#       if defined(_MPI)
            blocklengths(1) = 1
            blocklengths(2) = 1
            blocklengths(3) = 1
            blocklengths(4) = 1

            disps(1) = 0
            disps(2) = loc(node%data_pers%r) - loc(node)
            disps(3) = loc(node%data_temp%mat_diagonal) - loc(node)
            disps(4) = sizeof(node)

            types(1) = MPI_LB
            types(2) = MPI_DOUBLE_PRECISION
            types(3) = MPI_DOUBLE_PRECISION
            types(4) = MPI_UB

            call MPI_Type_struct(4, blocklengths, disps, types, mpi_node_type, i_error); assert_eq(i_error, 0)
            call MPI_Type_commit(mpi_node_type, i_error); assert_eq(i_error, 0)

            call MPI_Type_extent(mpi_node_type, extent, i_error); assert_eq(i_error, 0)
            assert_eq(sizeof(node), extent)

            call MPI_Type_size(mpi_node_type, extent, i_error); assert_eq(i_error, 0)
            assert_eq(16, extent)
#       endif
    end subroutine

    subroutine create_edge_mpi_type(mpi_edge_type)
        integer, intent(out)            :: mpi_edge_type

        type(t_edge_data)               :: edge
        integer                         :: blocklengths(2), types(2), disps(2), i_error, extent

#       if defined(_MPI)
            blocklengths(1) = 1
            blocklengths(2) = 1

            disps(1) = 0
            disps(2) = sizeof(edge)

            types(1) = MPI_LB
            types(2) = MPI_UB

            call MPI_Type_struct(2, blocklengths, disps, types, mpi_edge_type, i_error); assert_eq(i_error, 0)
            call MPI_Type_commit(mpi_edge_type, i_error); assert_eq(i_error, 0)

            call MPI_Type_extent(mpi_edge_type, extent, i_error); assert_eq(i_error, 0)
            assert_eq(sizeof(edge), extent)

            call MPI_Type_size(mpi_edge_type, extent, i_error); assert_eq(i_error, 0)
            assert_eq(0, extent)
#       endif
    end subroutine

    subroutine pre_traversal_grid_op(traversal, grid)
        type(_T_CG_(exact_traversal)), intent(inout)					:: traversal
        type(t_grid), intent(inout)							        :: grid
    end subroutine

    subroutine post_traversal_grid_op(traversal, grid)
        type(_T_CG_(exact_traversal)), intent(inout)			    :: traversal
        type(t_grid), intent(inout)							        :: grid

        integer                                                     :: i_error
        real (kind = GRID_SR)                                       :: reduction_set(2)

        call reduce(traversal%r_C_r, traversal%children%r_C_r, MPI_SUM, .false.)
        call reduce(traversal%r_sq, traversal%children%r_sq, MPI_SUM, .false.)

        reduction_set(1) = traversal%r_C_r
        reduction_set(2) = traversal%r_sq

        call reduce(reduction_set, MPI_SUM)

        traversal%r_C_r = reduction_set(1)
        traversal%r_sq = reduction_set(2)
    end subroutine

    subroutine pre_traversal_op(traversal, section)
        type(_T_CG_(exact_traversal)), intent(inout)					:: traversal
        type(t_grid_section), intent(inout)							:: section

        traversal%r_C_r = 0.0_GRID_SR
        traversal%r_sq = 0.0_GRID_SR
    end subroutine

    !*******************************
    !Geometry operators
    !*******************************

    elemental subroutine node_first_touch_op(traversal, section, node)
        type(_T_CG_(exact_traversal)), intent(in)	    :: traversal
        type(t_grid_section), intent(in)		    :: section
        type(t_node_data), intent(inout)		    :: node

        real(kind = GRID_SR)                        :: r(_gv_node_size)
        real(kind = GRID_SR)                        :: rhs(_gv_node_size)
        real(kind = GRID_SR)                        :: trace_A(_gv_node_size)

#       if defined(_gv_rhs)
            call gv_rhs%read(node, rhs)
#       else
            rhs = 0.0_GRID_SR
#       endif

        call pre_dof_op(r, rhs, trace_A)

        call gv_r%write(node, r)
        call gv_trace_A%write(node, trace_A)
    end subroutine

    subroutine element_op(traversal, section, element)
        type(_T_CG_(exact_traversal)), intent(inout)		:: traversal
        type(t_grid_section), intent(inout)				:: section
        type(t_element_base), intent(inout), target		:: element

        !local variables
        integer :: i
        real(kind = GRID_SR)	:: x(_gv_size), r(_gv_size), trace_A(_gv_size)
        real(kind = GRID_SR)	:: A(_gv_size, _gv_size)

        call gv_x%read(element, x)
        call gm_A%read(element, A)

        !add up matrix diagonal
        forall (i = 1 : _gv_size)
            trace_A(i) = A(i, i)
        end forall

        r = -matmul(A, x)

        call gv_r%add(element, r)
        call gv_trace_A%add(element, trace_A)
    end subroutine

    elemental subroutine node_last_touch_op(traversal, section, node)
        type(_T_CG_(exact_traversal)), intent(in)			:: traversal
        type(t_grid_section), intent(in)				:: section
        type(t_node_data), intent(inout)				:: node

        logical                 :: is_dirichlet(1)
        real(kind = GRID_SR)	:: r(_gv_node_size)

        call gv_dirichlet%read(node, is_dirichlet)

        if (.not. any(is_dirichlet)) then
            call inner_node_last_touch_op(traversal, section, node)
        else
            r(:) = 0.0_GRID_SR

            call gv_r%write(node, r)
        end if
    end subroutine

    elemental subroutine inner_node_last_touch_op(traversal, section, node)
        type(_T_CG_(exact_traversal)), intent(in)			:: traversal
        type(t_grid_section), intent(in)				:: section
        type(t_node_data), intent(inout)				:: node

        real(kind = GRID_SR)                        :: r(_gv_node_size)
        real(kind = GRID_SR)                        :: trace_A(_gv_node_size)

        call gv_r%read(node, r)
        call gv_trace_A%read(node, trace_A)

        call post_dof_op(r, trace_A)

        call gv_r%write(node, r)
    end subroutine

    pure subroutine node_reduce_op(traversal, section, node)
        type(_T_CG_(exact_traversal)), intent(inout)  :: traversal
        type(t_grid_section), intent(in)		    :: section
        type(t_node_data), intent(in)				:: node

        logical :: is_dirichlet(1)

        call gv_dirichlet%read(node, is_dirichlet)

        if (.not. any(is_dirichlet)) then
            call inner_node_reduce_op(traversal, section, node)
        end if
    end subroutine

    pure subroutine inner_node_reduce_op(traversal, section, node)
        type(_T_CG_(exact_traversal)), intent(inout)	    :: traversal
        type(t_grid_section), intent(in)			    :: section
        type(t_node_data), intent(in)				    :: node

        integer											:: i

        real (kind = GRID_SR) :: r(_gv_node_size)
        real (kind = GRID_SR) :: trace_A(_gv_node_size)

        call gv_r%read(node, r)
        call gv_trace_A%read(node, trace_A)

        do i = 1, _gv_node_size
            call reduce_dof_op(traversal%r_C_r, traversal%r_sq, r(i), trace_A(i))
        end do
    end subroutine

    pure subroutine node_merge_op(local_node, neighbor_node)
        type(t_node_data), intent(inout)			    :: local_node
        type(t_node_data), intent(in)				    :: neighbor_node

        real (kind = GRID_SR) :: r(_gv_node_size)
        real (kind = GRID_SR) :: trace_A(_gv_node_size)

        call gv_r%read(neighbor_node, r)
        call gv_r%add(local_node, r)

        call gv_trace_A%read(neighbor_node, trace_A)
        call gv_trace_A%add(local_node, trace_A)
    end subroutine

    pure subroutine node_write_op(local_node, neighbor_node)
        type(t_node_data), intent(inout)			    :: local_node
        type(t_node_data), intent(in)				    :: neighbor_node

        real (kind = GRID_SR) :: r(_gv_node_size)
        real (kind = GRID_SR) :: trace_A(_gv_node_size)

        assert_pure(neighbor_node%data_temp%mat_diagonal(1) .ge. local_node%data_temp%mat_diagonal(1))

        call gv_r%read(neighbor_node, r)
        call gv_r%write(local_node, r)

        call gv_trace_A%read(neighbor_node, trace_A)
        call gv_trace_A%write(local_node, trace_A)
    end subroutine

    !*******************************
    !Volume and DoF operators
    !*******************************

    elemental subroutine pre_dof_op(r, rhs, trace_A)
        real (kind = GRID_SR), intent(out)			:: r
        real (kind = GRID_SR), intent(in)			:: rhs
        real (kind = GRID_SR), intent(out)			:: trace_A

        r = rhs
        trace_A = tiny(1.0_GRID_SR)
    end subroutine

    elemental subroutine post_dof_op(r, trace_A)
        real (kind = GRID_SR), intent(inout)		:: r
        real (kind = GRID_SR), intent(in)			:: trace_A

        r = r / trace_A
    end subroutine

    elemental subroutine reduce_dof_op(r_C_r, r_sq, r, trace_A)
        real (kind = GRID_SR), intent(inout)		:: r_C_r
        real (kind = GRID_SR), intent(inout)		:: r_sq
        real (kind = GRID_SR), intent(in)		    :: r
        real (kind = GRID_SR), intent(in)			:: trace_A

        r_C_r = r_C_r + (r * trace_A * r)
        r_sq = r_sq + (r * r)
    end subroutine
END MODULE

MODULE _CG
    use SFC_edge_traversal

    use linear_solver
    use _CG_(step)
    use _CG_(exact)

    implicit none

    type, extends(t_linear_solver)      :: _T_CG
        real (kind = GRID_SR)           :: max_error
        integer (kind = GRID_SI)        :: i_restart_interval
        type(_T_CG_(step_traversal))    :: cg_step
        type(_T_CG_(exact_traversal))   :: cg_exact

        contains

        procedure, pass :: create
        procedure, pass :: destroy
        procedure, pass :: solve
        procedure, pass :: reduce_stats
        procedure, pass :: clear_stats
    end type

    private
    public _T_CG

    contains

    subroutine create(solver, max_error, i_restart_interval)
        class(_T_CG), intent(inout)             :: solver
        real (kind = GRID_SR), intent(in)       :: max_error
        integer (kind = GRID_SI), intent(in)    :: i_restart_interval

        call solver%cg_step%create()
        call solver%cg_exact%create()

        solver%max_error = max_error
        solver%i_restart_interval = i_restart_interval
    end subroutine

    subroutine destroy(solver)
        class(_T_CG), intent(inout)             :: solver

        call solver%cg_step%destroy()
        call solver%cg_exact%destroy()
    end subroutine

    !> Solves a linear equation system using a CG solver
    !> \returns		number of iterations performed
    function solve(solver, grid) result(i_iteration)
        class(_T_CG), intent(inout)			    :: solver
        type(t_grid), intent(inout)			    :: grid

        integer (kind = GRID_SI)			    :: i_iteration
        real (kind = GRID_SR)				    :: r_sq, d_u, r_u, v_u, r_C_r, r_C_r_old, alpha, beta

        !$omp master
        _log_write(3, '(2X, A, ES14.7)') "CG solver, max residual error:", solver%max_error
        !$omp end master

        !set step sizes to 0
        alpha = 0.0_GRID_SR
        beta = 0.0_GRID_SR

        !compute initial residual

        call solver%cg_exact%traverse(grid)
        r_sq = solver%cg_exact%r_sq
        r_C_r = solver%cg_exact%r_C_r
        _log_write(2, '(4X, A, ES17.10, A, ES17.10)') "r^T r: ", r_sq, " r^T C r: ", r_C_r

        do i_iteration = 0, huge(1_GRID_SI)
            !$omp master
            _log_write(2, '(3X, A, I0, A, F0.10, A, F0.10, A, ES17.10)')  "i: ", i_iteration, ", alpha: ", alpha, ", beta: ", beta, ", res: ", sqrt(r_sq)
            !$omp end master

            if (r_sq < solver%max_error * solver%max_error) then
                exit
            end if

            !Apply unknowns update (x = x + alpha * d) and residual update (r = r - alpha * v)
            !Then, compute search direction (d = r + beta * d), and residual update (v = C^(⁻1) A d)
            solver%cg_step%alpha = alpha
            solver%cg_step%beta = beta
            call solver%cg_step%traverse(grid)
            r_C_r = solver%cg_step%r_C_r
            r_sq = solver%cg_step%r_sq
            d_u = solver%cg_step%d_u
            v_u = solver%cg_step%v_u

#           if !defined(_solver_unstable)
                r_u = solver%cg_step%r_u
#           endif

            !every once in a while, we compute the residual r = b - A x explicitly to limit the numerical error
            if (mod(i_iteration + 1, solver%i_restart_interval) == 0) then
                call solver%cg_exact%traverse(grid)
                r_C_r = solver%cg_exact%r_C_r
                r_sq = solver%cg_exact%r_sq

                if (r_sq < solver%max_error * solver%max_error) then
                    exit
                end if

                !$omp master
                if (iand(i_iteration, z'3ff') == z'3ff') then
                    _log_write(1, '(3X, A, I0, A, F0.10, A, F0.10, A, ES17.10)')  "i: ", i_iteration, ", alpha: ", alpha, ", beta: ", beta, ", res: ", sqrt(r_sq)
                end if
                !$omp end master
            end if

            !compute step size alpha = r^T C r / d^T A d
            alpha = r_C_r / d_u
            r_C_r_old = r_C_r

#           if !defined(_solver_unstable)
                r_C_r = r_C_r_old + alpha * (alpha * v_u - 2.0_GRID_SR * r_u)
                !r_C_r = alpha * (alpha * v_u - r_u)
#           else
                !requires one less dot product
                r_C_r = alpha * alpha * v_u - r_C_r_old
#           endif

            !compute beta = r^T C r (new) / r^T C r (old)
            beta = r_C_r / r_C_r_old

            _log_write(2, '(4X, A, ES17.10)') "d^T A d: ", d_u
            _log_write(2, '(4X, A, ES17.10, A, ES17.10)') "r^T r: ", r_sq, " r^T C r: ", r_C_r
        end do

        !$omp master
        _log_write(2, '(2X, A, T24, I0)') "CG iterations:", i_iteration
        !$omp end master
    end function

    subroutine reduce_stats(solver, mpi_op, global)
        class(_T_CG), intent(inout)     :: solver
        integer, intent(in)             :: mpi_op
        logical                         :: global

        call solver%cg_step%reduce_stats(mpi_op, global)
        call solver%cg_exact%reduce_stats(mpi_op, global)
        solver%stats = solver%cg_step%stats + solver%cg_exact%stats
    end subroutine

    subroutine clear_stats(solver)
        class(_T_CG), intent(inout)   :: solver

        call solver%cg_step%clear_stats()
        call solver%cg_exact%clear_stats()
        call solver%stats%clear()
    end subroutine
END MODULE

#undef _solver
#undef _solver_use
