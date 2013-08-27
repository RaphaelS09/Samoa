! Sam(oa)² - SFCs and Adaptive Meshes for Oceanic And Other Applications
! Copyright (C) 2010 Oliver Meister, Kaveh Rahnema
! This program is licensed under the GPL, for details see the file LICENSE


#include "Compilation_control.f90"

#if defined(_PYOP2)
	MODULE pyop2_adaptive_traversal
		use SFC_edge_traversal
		use Conformity
		use Samoa

        implicit none

        type num_traversal_data
            !additional data definitions
        end type

#		define	_GT_NAME					    t_pyop2_adaptive_traversal

#		define _GT_EDGES
#		define _GT_NODES

#		define _GT_TRANSFER_OP				    transfer_op
#		define _GT_REFINE_OP				    refine_op
#		define _GT_COARSEN_OP				    coarsen_op

#		include "SFC_generic_adaptive_traversal.f90"

		!******************
		!Geometry operators
		!******************

		subroutine transfer_op(traversal, section, src_element, dest_element)
 			type(t_pyop2_adaptive_traversal), intent(inout)							:: traversal
 			type(t_grid_section), intent(inout)							            :: section
			type(t_traversal_element), intent(inout)									:: src_element
			type(t_traversal_element), intent(inout)									:: dest_element


		end subroutine

		subroutine refine_op(traversal, section, src_element, dest_element, refinement_path)
 			type(t_pyop2_adaptive_traversal), intent(inout)							:: traversal
 			type(t_grid_section), intent(inout)										:: section
			type(t_traversal_element), intent(inout)								:: src_element
			type(t_traversal_element), intent(inout)								:: dest_element
			integer, dimension(:), intent(in)										:: refinement_path


		end subroutine

		subroutine coarsen_op(traversal, section, src_element, dest_element, refinement_path)
  			type(t_pyop2_adaptive_traversal), intent(inout)							:: traversal
			type(t_grid_section), intent(inout)													:: section
			type(t_traversal_element), intent(inout)									:: src_element
			type(t_traversal_element), intent(inout)									:: dest_element
			integer, dimension(:), intent(in)											:: refinement_path


		end subroutine
	END MODULE
#endif
