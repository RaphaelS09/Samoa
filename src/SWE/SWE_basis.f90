! Sam(oa)² - SFCs and Adaptive Meshes for Oceanic And Other Applications
! Copyright (C) 2010 Oliver Meister, Kaveh Rahnema
! This program is licensed under the GPL, for details see the file LICENSE


#include "Compilation_control.f90"

#if defined(_SWE)
#	include "dunavant.f90"

	!*****
	!Bases
	!*****

	MODULE SWE_Q_space
		use SFC_data_types

#		define _BF_TYPE_NAME		t_basis_Q
#		define _BF_ORDER			_SWE_ORDER

#		include "Tools_lagrange_basis.f90"
	END MODULE

	MODULE SWE_nh_node_space
		use SFC_data_types

#		define _BF_TYPE_NAME		t_basis_lin_node
#		define _BF_ORDER			1

#		include "Tools_lagrange_basis.f90"
	END MODULE


	MODULE SWE_flux_space
		use SFC_data_types

#		define _BF_TYPE_NAME		t_basis_flux
#		define _BF_ORDER			_SWE_ORDER

#		include "Tools_boundary_basis.f90"
	END MODULE



	!****************
	!Quadrature rules
	!****************

	MODULE Samoa_swe
		use SWE_lfs_flux
		use SWE_gv_Q


		use SWE_gm_A_mod
        use SWE_gv_qp_mod
        use SWE_gv_w_mod
        use SWE_gv_mat_diagonal_mod
        use SWE_gv_r_mod
        use SWE_gv_A_d_mod
        use SWE_gv_d_mod
        use SWE_gv_div_mod
        use SWE_gv_div_old_mod
        use SWE_gv_is_dirichlet_boundary_mod
        use SWE_gv_rhs_mod
        use SWE_gv_original_lse_orientation_mod
        use SWE_gv_h_old
		use SWE_Q_space
		use SWE_flux_space
		use SWE_nh_node_space

		use Samoa

		PUBLIC
	END MODULE
#endif
