! V0main.f90

!************************************************************************************************!
! @ Amanda Michaud, v1: 10/6/2014; current: 10/31/2014
! @ David Wiczer, v2: 03/31/2015
!-----------------------------------------------------
!************************************************************************************************!
! compiler line: gfortran -fopenmp -ffree-line-length-none -g V0para.f90 V0main.f90 -lblas -llapack -lgomp -lnlopt -o V0main.out  
!       	     ifort -mkl -qopenmp -parallel -O3 -xhost V0para.f90 V0main.f90 -lnlopt -o V0main.out
!       	     ifort -mkl -init=snan -init=array -g V0para.f90 V0main.f90 -lnlopt -o V0main_dbg.out
! val grind line: valgrind --leak-check=yes --error-limit=no --track-origins=yes --log-file=V0valgrind.log ./V0main_dbg.out &
module helper_funs
	
	use V0para
	implicit none
	
	!**********************************************************!
	!Public Policy Functions
	!	1)UI(e)		Unemployment Insurance
	!	2)SSDI(e,a)	DI (can be asset tested)
	!	3)SSret(e)	Social Sec. Retirement
	! 	4)xifun(d,z,t)	Acceptance probability
	!Utility Functions
	!	5)u(c,d,w)	w=1 if working; 2 if not
	!Earnings Index
	!	6)Hearn(t,e,w)	t=age, e=past index, w=current wage
	!Wage Function
	!	7) wage(bi,ai,d,z,t) indiv(beta,alf),disability,tfp,age
	!Locate Function
	!	8)finder(xx,x)	xx is grid, x is point, returns higher bound
	!Writing Subroutines
	!	9)  mat2csv(A,fname,append)   A=matrix, fname=file, append={0,1}
	!	10)  mati2csv(A,fname,append)  A=matrix, fname=file, append={0,1}: A is integer
	!	11) vec2csv(A,fname,append)   A=matrix, fname=file, append={0,1}
	!	12) veci2csv(A,fname,append)   A=matrix, fname=file, append={0,1}: A is integer
	!User-Defined Types (Structures) for value functiIons and policy functions
	!	a) val_struct: VR, VD, VN, VW, VU, V
	!	b) pol_struct: aR, aD,aU,aN,aW,gapp,gwork, gapp_dif,gwork_dif
	!	c) moments_structs
	!	d) hist_struct
	!**********************************************************!
	
	
	!------------------------------------------------------------------
	! a) val_struct: VR, VD, VN, VW, VU, V
	!------------------------------------------------------------------
	type val_struct
		real(dp), allocatable:: 	VR(:,:,:), &		!Retirement
					VD(:,:,:,:), &		!Disabled
					VN(:,:,:,:,:,:,:), &	!Long-term Unemployed
					VW(:,:,:,:,:,:,:), &	!Working
					VU(:,:,:,:,:,:,:), &	!Unemployed
					V(:,:,:,:,:,:,:)	!Participant
		integer :: alloced 	! status indicator
		integer :: inited 	! intiialized indicator
		
	end type	
	
	!------------------------------------------------------------------
	!	b) pol_struct: aR, aD,aU,aN,aW,gapp,gwork, gapp_dif,gwork_dif
	!------------------------------------------------------------------
	type pol_struct
		
		real(dp), allocatable ::	gapp_dif(:,:,:,:,:,:,:), &
					gwork_dif(:,:,:,:,:,:,:) ! latent value of work/apply
		integer, allocatable ::	aR(:,:,:), aD(:,:,:,:), aU(:,:,:,:,:,:,:), &
					aN(:,:,:,:,:,:,:), aW(:,:,:,:,:,:,:)
		integer, allocatable ::	gapp(:,:,:,:,:,:,:), &

					gwork(:,:,:,:,:,:,:) !integer choice of apply/work
		integer :: alloced
	end type

	type moments_struct
		real(dp) :: work_coefs(Nk), di_coefs(Nk),ts_emp_coefs(nj+1)
		real(dp) :: di_rate(TT-1), work_rate(TT-1), accept_rate(TT-1) !by age
		integer :: alloced
		real(dp) :: work_cov_coefs(Nk,Nk),di_cov_coefs(Nk,Nk),ts_emp_cov_coefs(nj+1,nj+1)
		real(dp) :: s2, avg_hlth_acc,avg_di,init_hlth_acc,init_di
		real(dp) :: hlth_acc_rt(TT-1)

	end type 

	type hist_struct
		real(dp), allocatable :: work_dif_hist(:,:), app_dif_hist(:,:) !choose work or not, apply or not -- latent value
		real(dp), allocatable :: di_prob_hist(:,:) !choose apply or not * prob of getting it-- latent value
		integer, allocatable :: hlth_voc_hist(:,:)
		real(dp), allocatable :: hlthprob_hist(:,:)
		real(dp), allocatable :: wage_hist(:,:) !realized wages
		integer, allocatable :: z_jt_macroint(:) !endogenous realization of shocks given a sequence
		real(dp), allocatable :: z_jt_panel(:,:)
		! a bunch of explanitory variables to be stacked on each other
		integer, allocatable :: status_hist(:,:) !status: W,U,N,D,R (1:5)
		integer, allocatable :: d_hist(:,:)
		real(dp), allocatable :: a_hist(:,:)
		real(dp), allocatable :: occgrow_jt(:,:)
		real(dp), allocatable :: occshrink_jt(:,:)
		real(dp), allocatable :: occsize_jt(:,:)
		integer :: alloced
	end type
	
	type shocks_struct
		! arrays related to randomly drawn stuff
		integer, allocatable :: j_i(:)
		real(dp), allocatable :: z_jt_select(:), z_jt_innov(:)
		integer, allocatable :: al_int_hist(:,:)
		integer, allocatable :: age_hist(:,:), born_hist(:,:), del_i_int(:), fndsep_i_int(:,:,:)
		real(dp), allocatable:: age_draw(:,:)
		real(dp), allocatable :: al_hist(:,:), del_i_draw(:),fndsep_i_draw(:,:),fndarrive_draw(:,:)
		
		real(dp), allocatable    :: status_it_innov(:,:),health_it_innov(:,:)
		real(dp), allocatable    :: jshock_ij(:,:)
		integer,  allocatable    :: drawi_ititer(:,:)
		integer,  allocatable    :: drawt_ititer(:,:)
		
		integer :: alloced
		integer :: drawn
	end type
	
	
	type val_pol_shocks_struct
	
		! try to do this with pointers
		type(shocks_struct), pointer :: shk_ptr
		type(val_struct)   , pointer :: vfs_ptr
		type(pol_struct)   , pointer :: pfs_ptr
	
		integer :: pointed
	end type
	
	contains

	!------------------------------------------------------------------------
	!1)UI(e): Unemployment Insurance
	!----------------
	function UI(ein)
	!----------------
	
		real(dp), intent(in)	:: ein 
		real(dp) 		:: UI
		!I'm using a replacement rate of UIrr % for now, can be fancier
		UI = ein*UIrr

	end function
	!------------------------------------------------------------------------
	!2) DI (can be asset tested)
	!---------------------
	function SSDI(ein)
	!---------------------
	 
	
		real(dp), intent(in)	:: ein
		real(dp) 		:: SSDI
		!Follows Pistafferi & Low '12
		IF (ein<DItest1*wmean) then
			SSDI = 0.9*ein
		ELSEIF (ein<DItest2*wmean) then
			SSDI = 0.9*DItest1*wmean + 0.32*(ein-DItest1*wmean)
		ELSEIF (ein<DItest3*wmean) then
			SSDI = 0.9*DItest1*wmean + 0.32*(ein-DItest1*wmean)+0.15*(ein-DItest2*wmean)
		ELSE
			SSDI = 0.9*DItest1*wmean + 0.32*(ein-DItest1*wmean)+0.15*(DItest3*wmean-DItest2*wmean)
		END IF

	end function
	!------------------------------------------------------------------------
	!3) Social Sec. Retirement	
	!--------------------
	function SSret(ein)
	!--------------------
	 
		real(dp), intent(in)	:: ein
		real(dp)			:: SSret
		
		!Follows Pistafferi & Low '15
		IF (ein<DItest1*wmean) then
			SSret = 0.9*ein
		ELSEIF (ein<DItest2*wmean) then
			SSret = 0.9*DItest1*wmean + 0.32*(ein-DItest1*wmean)
		ELSEIF (ein<DItest3*wmean) then
			SSret = 0.9*DItest1*wmean + 0.32*(ein-DItest1*wmean)+0.15*(ein-DItest2*wmean)
		ELSE
			SSret = 0.9*DItest1*wmean + 0.32*(ein-DItest1*wmean)+0.15*(DItest3*wmean-DItest2*wmean)
		END IF

	end function
	!------------------------------------------------------------------------
	! 4) Acceptance probability
	!--------------------
	function xifun(idin,trin,itin,hlthprob)

		real(dp), intent(in):: trin
		integer, intent(in):: idin,itin
		real(dp), optional :: hlthprob
		real(dp) :: xifunH,xifunV,xifun, hlthfrac
		
		!stage 1-3
		xifunH = xi_d(idin)
		!adjsut for time aggregation in first stage?
	!	xifunH = 1._dp - max(0.,1.-xifunH)**(1._dp/proc_time1)
		
		!vocational stages 4-5
		if(itin>=(TT-2)) then
			xifunV =  (maxval(trgrid)-trin)/((maxval(trgrid)-minval(trgrid)))*xizcoef*(1.+xiagecoef)
		else
			xifunV =  (maxval(trgrid)-trin)/((maxval(trgrid)-minval(trgrid)))*xizcoef
		endif
		!adjust for time aggregation in second stage?
	!	xifunV = 1._dp - max(0._dp,1.-xifunV)**(1._dp/proc_time2)
		
		xifun = xifunV + xifunH
	
		hlthfrac = xifunH/xifun
		
		
		!adjust for time aggregation all at once
		xifun = 1._dp - max(0._dp,1._dp-xifun)**(1._dp/proc_time1)
		
		xifun = min(xifun,1._dp)

		if((itin .eq. 1) .and. (ineligNoNu .eqv. .false.)) then
			xifun = xifun*eligY
		endif
		if(present(hlthprob) .eqv. .true.) &
			hlthprob = hlthfrac*xifun
		
	end function

	!------------------------------------------------------------------------
	! 4) Utility Function
	!--------------------
	function util(cin,din,wkin)
	!--------------------
	 
		real(dp),intent(in)	:: cin
		integer, intent(in)	:: din, wkin
		real(dp)			:: util
		
		
		if ((wkin .gt. 1) .or. (din .gt. 1)) then
			if(gam> 1+1e-5_dp .or. gam < 1-1e-5_dp) then
				util = ((cin*dexp(theta*dble(din-1)+eta*dble(wkin-1)))**(1._dp-gam) )/(1._dp-gam)
			else 
				util = dlog(cin*dexp(theta*dble(din-1)+eta*dble(wkin-1)))
			endif
		else 
			if(gam> 1._dp+1e-5_dp .or. gam < 1_dp-1e-5_dp) then
				util = (cin**(1._dp-gam))/(1._dp-gam)
			else
				util = dlog(cin)
			endif
		end if
		util = util + util_const

	end function

	!------------------------------------------------------------------------
	! 5) Earnings Index Function
	!--------------------
	function Hearn(tin,ein,wgin)
	!--------------------
	
		real(dp), intent(in)	:: wgin
		integer, intent(in)	:: ein, tin
		real(dp)			:: Hearn

		Hearn = wgin/(tlen*dble(agegrid(tin))) + egrid(ein)*(1._dp-1._dp/(tlen*dble(agegrid(tin))))
	
	end function

	!------------------------------------------------------------------------
	! 6) Wage Function
	!--------------------
	function wage(levin,aiin,din,zin,tin)
	!--------------------
	
		real(dp), intent(in)	:: levin, aiin, zin
		integer, intent(in)	:: din, tin
		real(dp)			:: wage
		if( z_flowrts .eqv. .true.) then
			wage = dexp( levin + aiin+wd(din)+wtau(tin) ) 
		else 
			wage = dexp( levin + aiin+wd(din)+wtau(tin) + zin ) 
		endif

	end function

	!------------------------------------------------------------------------
	! 7) Locate Function
	!--------------------
	function finder(xx,x)
	!--------------------

		real(dp), dimension(:), intent(IN) :: xx
		real(dp), intent(IN) :: x
		integer :: locate,finder
		integer :: nf,il,im,iu
		
		nf=size(xx)
		il=0
		iu=nf+1 
		do
			if (iu-il <= 1) exit !converged

			im=(iu+il)/2
			
			if (x >= xx(im)) then
				il=im
			else
				iu=im
			end if
		end do
		if (x <= xx(1)+epsilon(xx(1))) then
			locate=1
		else if (x >= xx(nf)-epsilon(xx(nf))) then
			locate=nf-1
		else
			locate=il
		end if
		finder = locate
	end function

	!------------------------------------------------------------------------
	! 8) Write a Matrix to .csv
	!--------------------
	subroutine mat2csv(A,fname,append)
	!--------------------
	! A: name of matrix
	! fname: name of file, should end in ".csv"
	! append: a 1 or 0.  1 if matrx should add to end of existing file, 0, to overwrite.
	
	real(dp), dimension(:,:), intent(in) :: A
	character(LEN=*), intent(in) :: fname
	integer, intent(in), optional :: append
	CHARACTER(LEN=*), PARAMETER  :: FMT = "(G20.12)"
	CHARACTER(LEN=20) :: FMT_1
	integer :: r,c,ri,ci
	r = size(A,1)
	c = size(A,2)
	if(present(append)) then
		if(append .eq. 1) then 
			open(1, file=fname,ACCESS='APPEND', POSITION='APPEND')
		else
			open(1, file=fname)
		endif
	else
		open(1, file=fname)
	endif
	write(FMT_1, "(A1,I2,A7)") "(", c, "G20.12)"
	do ri=1,r
		!write(1,FMT_1) (A(ri,ci), ci = 1,c)
		do ci = 1,c-1
			write(1,FMT, advance='no') A(ri,ci)
		enddo
		write(1,FMT) A(ri,c)
	enddo
	write(1,*) " "! trailing space
	close(1)

	end subroutine mat2csv

	!------------------------------------------------------------------------
	! 9) Write a Matrix to .csv
	!--------------------
	subroutine mati2csv(A,fname,append)
	!--------------------

	integer, dimension(:,:), intent(in) :: A
	character(LEN=*), intent(in) :: fname
	integer, intent(in), optional :: append
	CHARACTER(LEN=*), PARAMETER  :: FMT = "(I8.1)"
	integer :: r,c,ri,ci
	r = size(A,1)
	c = size(A,2)
	if(present(append)) then
		if(append .eq. 1) then 
			open(1, file=fname,ACCESS='APPEND', POSITION='APPEND')
		else
			open(1, file=fname)
		endif
	else
		open(1, file=fname)
	endif

	do ri=1,r
		do ci = 1,c-1
			write(1,FMT, advance='no') A(ri,ci)
		enddo
		write(1,FMT) A(ri,c)
	enddo
	write(1,*) " "! trailing space
	close(1)

	end subroutine mati2csv


	!------------------------------------------------------------------------
	! 10) Write a Vector to .csv
	!--------------------
	subroutine vec2csv(A,fname,append)
	!--------------------

	real(dp), dimension(:), intent(in) :: A
	character(len=*), intent(in) :: fname
	integer, intent(in), optional :: append
	integer :: r,ri
	r = size(A,1)
	if(present(append)) then
		if(append .eq. 1) then 
			open(1, file=fname,ACCESS='APPEND', POSITION='APPEND')
		else
			open(1, file=fname)
		endif
	else
		open(1, file=fname) 
	endif
	do ri=1,r
		write(1,*) A(ri)
	end do
	write(1,*) " "! trailing space
	close(1)

	end subroutine vec2csv


	!------------------------------------------------------------------------
	! 11) Write a Vector to .csv
	!--------------------
	subroutine veci2csv(A,fname,append)
	!--------------------

		integer, dimension(:), intent(in) :: A
		character(len=*), intent(in) :: fname
		integer, intent(in), optional :: append
		integer :: r,ri
		r = size(A,1)
		if(present(append)) then
			if(append .eq. 1) then 
				open(1, file=fname,ACCESS='APPEND', POSITION='APPEND')
			else
				open(1, file=fname)
			endif
		else
			open(1, file=fname) 
		endif
		do ri=1,r
			write(1,*) A(ri)
		end do
		write(1,*) " "! trailing space
		close(1)

	end subroutine veci2csv
	

	!------------------------------------------------------------------------
	! 12) Run an OLS regression
	!------------------------------------------------------------------------
	subroutine OLS(XX,Y,coefs,cov_coef, hatsig2, status)
		real(dp), dimension(:,:), intent(in) :: XX
		real(dp), dimension(:), intent(in) :: Y
		real(dp), dimension(:), intent(out) :: coefs
		real(dp), dimension(:,:), intent(out) :: cov_coef
		real(dp), intent(out) :: hatsig2
		integer, intent(out) :: status

		integer :: nX, nY, nK
		real(dp), dimension(:,:), allocatable :: XpX,XpX_fac,XpX_inv
		real(dp), dimension(:), allocatable :: fitted,resids
		integer :: i
		
		external dgemm,dgemv
		external dpotrs,dpotrf,dpotri

		nK = size(XX, dim = 2)
		nX = size(XX, dim = 1)
		nY = size(Y)
		
		allocate(XpX(nK,nK))
		allocate(XpX_fac(nK,nK))
		allocate(XpX_inv(nK,nK))
		allocate(fitted(nX))
		allocate(resids(nX))
		coefs = 0.
		cov_coef = 0.
		
		
		if(nY /= nX ) then
			if(verbose>0 ) print *, 'size of X and Y in regression not compatible'
			status = 1
		else 
			XpX = 0.
			call dgemm('T', 'N', nK, nK, nX, 1._dp, XX, nX, XX, nX, 0., XpX, nK)
			XpX_fac = XpX
			call dpotrf('U',Nk,XpX_fac,Nk,status)
			if(status .eq. 0) then
				! 3/ Multiply LHS of regression and solve it
				call dgemv('T', nX, nK, 1._dp, XX, nX, Y, 1, 0., coefs, 1)
				call dpotrs('U',nK,1,XpX_fac,nK,coefs,Nk,status)
			else 
				if(verbose >0 ) print *, "cannot factor XX"
			endif
		endif
		
		if(status .eq. 0) then 
			XpX_inv = XpX_fac
			call dpotri('U',nK,XpX_inv,nK,status)
			fitted = 0.
			call dgemv('N', nX, nK, 1._dp, XX, nX, coefs, 1, 0., fitted, 1)
			resids = Y - fitted
			hatsig2 = 0.
			do i=1,nY
				hatsig2 = (resids(i)**2)/dble(nX-nK) + hatsig2
			enddo
			if(status .eq. 0) cov_coef = hatsig2*XpX_inv
		endif
		
		deallocate(XpX,XpX_fac,XpX_inv,fitted,resids)
	
	end subroutine OLS

	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	! Time aggregation solution to pid
	subroutine cor_time_ag( pid_bian, pid_mo )
	
		real(dp), intent(in) , dimension(:,:,:) :: pid_bian
		real(dp), intent(out), dimension(:,:,:) :: pid_mo
		
		integer :: sz,i
		
		external dgees 
		
		pid_mo = pid_bian
		
		
	end subroutine cor_time_ag
		

	subroutine alloc_hist(hst)
	
		type(hist_struct) :: hst

		allocate(hst%wage_hist(Nsim,Tsim), stat=hst%alloced)
		allocate(hst%work_dif_hist(Nsim,Tsim), stat=hst%alloced)
		allocate(hst%app_dif_hist(Nsim,Tsim), stat=hst%alloced)
		allocate(hst%di_prob_hist(Nsim,Tsim), stat=hst%alloced)
		allocate(hst%hlth_voc_hist(Nsim,Tsim), stat=hst%alloced)
		allocate(hst%hlthprob_hist(Nsim,Tsim), stat=hst%alloced)
		allocate(hst%status_hist(Nsim,Tsim), stat=hst%alloced)
		allocate(hst%d_hist(Nsim,Tsim), stat=hst%alloced)
		allocate(hst%a_hist(Nsim,Tsim), stat=hst%alloced)
		allocate(hst%z_jt_macroint(Tsim), stat=hst%alloced)
		allocate(hst%z_jt_panel(nj,Tsim), stat=hst%alloced)
		allocate(hst%occgrow_jt(nj,Tsim), stat=hst%alloced)
		allocate(hst%occshrink_jt(nj,Tsim), stat=hst%alloced)
		allocate(hst%occsize_jt(nj,Tsim), stat=hst%alloced)
	
	end subroutine alloc_hist


	subroutine alloc_econ(vfs, pfs,hst)

	! Structure to communicate everything
		type(val_struct)   :: vfs
		type(pol_struct)   :: pfs
		type(hist_struct)  :: hst
		!************************************************************************************************!
		! Allocate phat matrices
		!************************************************************************************************!
		! (disability extent, earn hist, assets)
		allocate(vfs%VR(nd,ne,na), stat=vfs%alloced)
		allocate(pfs%aR(nd,ne,na), stat=pfs%alloced)

		! (disability extent, earn hist, assets, age)
		allocate(vfs%VD(nd,ne,na,TT), stat=vfs%alloced)
		allocate(pfs%aD(nd,ne,na,TT-1), stat=pfs%alloced)

		! (occupation X ind exposure, ind disb. risk X ind. wage, disab. extent, earn hist, assets, agg shock, age)
		allocate(vfs%VN(nl*ntr,ndi*nal,nd,ne,na,nz,TT), stat=vfs%alloced)
		allocate(vfs%VU(nl*ntr,ndi*nal,nd,ne,na,nz,TT), stat=vfs%alloced)
		allocate(vfs%VW(nl*ntr,ndi*nal,nd,ne,na,nz,TT), stat=vfs%alloced)
		allocate(vfs%V(nl*ntr,ndi*nal,nd,ne,na,nz,TT), stat=vfs%alloced)
		allocate(pfs%aN(nl*ntr,ndi*nal,nd,ne,na,nz,TT-1), stat=pfs%alloced)
		allocate(pfs%aW(nl*ntr,ndi*nal,nd,ne,na,nz,TT-1), stat=pfs%alloced)
		allocate(pfs%aU(nl*ntr,ndi*nal,nd,ne,na,nz,TT-1), stat=pfs%alloced)
		allocate(pfs%gwork(nl*ntr,ndi*nal,nd,ne,na,nz,TT-1), stat=pfs%alloced)
		allocate(pfs%gapp(nl*ntr,ndi*nal,nd,ne,na,nz,TT-1), stat=pfs%alloced)

		allocate(pfs%gapp_dif(nl*ntr,ndi*nal,nd,ne,na,nz,TT), stat=pfs%alloced)
		allocate(pfs%gwork_dif(nl*ntr,ndi*nal,nd,ne,na,nz,TT), stat=pfs%alloced)
		
		call alloc_hist(hst)

	end subroutine alloc_econ
	
	subroutine alloc_shocks(shk)
		
		type(shocks_struct) :: shk

		allocate(shk%age_hist(Nsim,Tsim), stat=shk%alloced)
		allocate(shk%age_draw(Nsim,Tsim+3), stat=shk%alloced)
		allocate(shk%al_hist(Nsim,Tsim), stat=shk%alloced)
		allocate(shk%al_int_hist(Nsim,Tsim), stat=shk%alloced)
		allocate(shk%born_hist(Nsim,Tsim), stat=shk%alloced)
		allocate(shk%del_i_int(Nsim), stat=shk%alloced)
		allocate(shk%del_i_draw(Nsim), stat=shk%alloced)
		allocate(shk%fndsep_i_draw(Nsim,2), stat=shk%alloced)
		allocate(shk%fndsep_i_int(Nsim,2,nz), stat=shk%alloced)
		allocate(shk%fndarrive_draw(Nsim,Tsim), stat=shk%alloced)
		!this must be big enough that we are sure it's big enough that can always find a worker
		allocate(shk%drawi_ititer(Nsim,1000), stat=shk%alloced) 
		allocate(shk%drawt_ititer(Nsim,1000), stat=shk%alloced)
		allocate(shk%j_i(Nsim), stat=shk%alloced)
		allocate(shk%jshock_ij(Nsim,nj), stat=shk%alloced)
		allocate(shk%status_it_innov(Nsim,Tsim), stat=shk%alloced)
		allocate(shk%health_it_innov(Nsim,Tsim), stat=shk%alloced)
		allocate(shk%z_jt_innov(Tsim))
		allocate(shk%z_jt_select(Tsim))

	
	
	end subroutine alloc_shocks
	

	subroutine dealloc_hist(hst)

		type(hist_struct) :: hst
		
		deallocate(hst%wage_hist , stat=hst%alloced)
		deallocate(hst%work_dif_hist , stat=hst%alloced)
		deallocate(hst%app_dif_hist , stat=hst%alloced)
		deallocate(hst%di_prob_hist , stat=hst%alloced)
		deallocate(hst%hlth_voc_hist, stat=hst%alloced)
		deallocate(hst%hlthprob_hist, stat=hst%alloced)
		deallocate(hst%status_hist , stat=hst%alloced)
		deallocate(hst%d_hist , stat=hst%alloced)
		deallocate(hst%a_hist , stat=hst%alloced)
		deallocate(hst%z_jt_macroint, stat=hst%alloced)
		deallocate(hst%z_jt_panel, stat=hst%alloced)
		deallocate(hst%occgrow_jt, stat=hst%alloced)
		deallocate(hst%occshrink_jt, stat=hst%alloced)
		deallocate(hst%occsize_jt, stat=hst%alloced)
		hst%alloced = 0
		
	end subroutine dealloc_hist

	subroutine dealloc_econ(vfs,pfs,hst)

	! Structure to communicate everything
		type(val_struct) :: vfs
		type(pol_struct) :: pfs
		type(hist_struct):: hst
		deallocate(vfs%VR, stat=vfs%alloced)
		deallocate(pfs%aR, stat=pfs%alloced)

		! (disability extent, earn hist, assets, age)
		deallocate(vfs%VD, stat=vfs%alloced)
		deallocate(pfs%aD, stat=pfs%alloced)

		! (occupation X ind exposure, ind disb. risk X ind. wage, disab. extent, earn hist, assets, agg shock, age)
		deallocate(vfs%VN , stat=vfs%alloced)
		deallocate(vfs%VU , stat=vfs%alloced)
		deallocate(vfs%VW , stat=vfs%alloced)
		deallocate(vfs%V , stat=vfs%alloced)
		deallocate(pfs%aN, stat=pfs%alloced)
		deallocate(pfs%aW, stat=pfs%alloced)
		deallocate(pfs%aU, stat=pfs%alloced)
		deallocate(pfs%gwork, stat=pfs%alloced)
		deallocate(pfs%gapp, stat=pfs%alloced)

		deallocate(pfs%gapp_dif , stat=pfs%alloced)
		deallocate(pfs%gwork_dif , stat=pfs%alloced)

		call dealloc_hist(hst)
	end subroutine dealloc_econ
	
	
	subroutine dealloc_shocks(shk)

		type(shocks_struct) :: shk

		deallocate(shk%age_hist , stat=shk%alloced)
		deallocate(shk%age_draw , stat=shk%alloced)
		deallocate(shk%born_hist , stat=shk%alloced)
		deallocate(shk%al_hist , stat=shk%alloced)
		deallocate(shk%al_int_hist , stat=shk%alloced)
		deallocate(shk%j_i , stat=shk%alloced)
		deallocate(shk%jshock_ij, stat=shk%alloced)
		deallocate(shk%status_it_innov , stat=shk%alloced)
		deallocate(shk%health_it_innov , stat=shk%alloced)
		deallocate(shk%del_i_int, stat=shk%alloced)
		deallocate(shk%del_i_draw, stat=shk%alloced)
		deallocate(shk%fndsep_i_int, stat=shk%alloced)
		deallocate(shk%fndsep_i_draw, stat=shk%alloced)
		deallocate(shk%fndarrive_draw, stat=shk%alloced)
		deallocate(shk%z_jt_innov)
		deallocate(shk%z_jt_select)
		!this must be big enough that we are sure it's big enough that can always find a worker
		deallocate(shk%drawi_ititer) 
		deallocate(shk%drawt_ititer)

	end subroutine dealloc_shocks

end module helper_funs

module model_data

	use V0para
	use helper_funs
	
	implicit none
	
	contains

	subroutine moments_compute(hst,moments_sim,shk)
	
		type(moments_struct) 	:: moments_sim
		type(hist_struct)	:: hst
		type(shocks_struct) :: shk
	
		integer :: i, ij,id,it,ial,st,si,age_hr,status_hr
		integer :: totage(TT),totD(TT),totW(TT),totst(Tsim),total(nal), tot3al(nal), &
				& tot3age(TT-1),totage_st(TT,Tsim),tot_applied(TT-1)

		real(dp) :: dD_age(TT), dD_t(Tsim),a_age(TT),a_t(Tsim),alworkdif(nal),alappdif(nal), &
				& workdif_age(TT-1), appdif_age(TT-1), alD(nal), alD_age(nal,TT-1), &
				& status_Nt(5,Tsim),DIatriskpop,napp_t,ninsur_app, dicont_hr=0.


		if(hst%alloced /= 0) then
			if(verbose >= 1) print *, "not correctly passing hists_struct to moments"
		endif

		!initialize all the sums
		totage	= 0
		totst	= 0
		totD	= 0
		totW	= 0
		total	= 0
		tot3al	= 0
		tot3age	= 0
		totage_st=0
		tot_applied = 0
				
		dD_age 		= 0._dp
		dD_t 		= 0._dp
		a_age 		= 0._dp
		a_t 		= 0._dp
		alD		= 0._dp
		alD_age		= 0._dp
		appdif_age 	= 0._dp
		workdif_age 	= 0._dp
		alworkdif	= 0._dp
		alappdif	= 0._dp
		status_Nt 	= 0._dp
		moments_sim%hlth_acc_rt = 0._dp
		moments_sim%avg_hlth_acc = 0._dp
		
		do si = 1,Nsim
			do st = 1,Tsim
				if((hst%status_hist(si,st)>0) .and. (shk%age_hist(si,st) >0) ) then
					age_hr = shk%age_hist(si,st)
					totage_st(age_hr,st) = totage_st(age_hr,st) + 1
					! savings and disability by time
					a_t(st) = hst%a_hist(si,st) + a_t(st)
					status_hr = hst%status_hist(si,st)
					if(status_hr == 4) dD_t(st) = dD_t(st)+hst%d_hist(si,st)
					
					status_Nt(status_hr,st) = 1._dp + status_Nt(status_hr,st)

					! disability by age and age X shock
					do it = 1,TT-1
						if(age_hr == it) then
							if(hst%status_hist(si,st) == 1) totW(age_hr) = totW(age_hr) + 1
							if(hst%status_hist(si,st) < 3) &
							&	workdif_age(age_hr) = workdif_age(age_hr) + hst%work_dif_hist(si,st)

							if(hst%hlth_voc_hist(si,st) >0) then
								moments_sim%hlth_acc_rt(it) = 2.- dble(hst%hlth_voc_hist(si,st)) + moments_sim%hlth_acc_rt(it)
								tot_applied(it) = tot_applied(it)+1
								moments_sim%avg_hlth_acc = 2.- dble(hst%hlth_voc_hist(si,st)) + moments_sim%avg_hlth_acc
							endif
							if(hst%status_hist(si,st) == 4) then
								totD(age_hr) = totD(age_hr) + 1
								dD_age(age_hr) = dD_age(age_hr)+hst%d_hist(si,st)
								! associate this with its shock
								do ial = 1,nal
									if(  (shk%al_hist(si,st) <= alfgrid(ial)+2*epsilon(1._dp)) &
									&	.and. (shk%al_hist(si,st) >= alfgrid(ial)-2*epsilon(1._dp)) &
									&	.and. (hst%status_hist(si,st) == 4 )) &
									&	alD_age(ial,age_hr) = 1._dp + alD_age(ial,it)
								enddo
							elseif(hst%status_hist(si,st) == 3) then
								appdif_age(it) = appdif_age(age_hr) + hst%app_dif_hist(si,st)
								tot3age(age_hr) = tot3age(age_hr) + 1							
							endif
						endif
					enddo !it = 1,TT-1
					! assets by age
					do it=1,TT
						if(age_hr == it) then
							a_age(it) = hst%a_hist(si,st) +a_age(it)
						endif
					enddo
					
					! disability and app choice by shock level
					do ial = 1,nal
						if( shk%al_hist(si,st) <= alfgrid(ial)+2*epsilon(1._dp) &
						&	.and. shk%al_hist(si,st) >= alfgrid(ial)-2*epsilon(1._dp)) then
							if(hst%status_hist(si,st) <3) then
								!work choice:
								alworkdif(ial) = alworkdif(ial) + hst%work_dif_hist(si,st)
								total(ial) = total(ial) + 1
							endif
							if(hst%status_hist(si,st) == 3) then
								alappdif(ial) = alappdif(ial) + hst%app_dif_hist(si,st)
								tot3al(ial) = tot3al(ial) + 1
							endif
							if(hst%status_hist(si,st) == 4) &
								& alD(ial) = 1._dp + alD(ial)
						endif
					enddo
				endif !status(si,st) >0
			enddo!st = 1,Tsim
		enddo ! si=1,Nsim

		!overall disability rate (the money stat)
		DIatriskpop =0._dp
		moments_sim%avg_di = 0._dp
		do st=1,Tsim
			DIatriskpop = sum(status_Nt(1:3,st)) + DIatriskpop
			moments_sim%avg_di = status_Nt(4,st) + moments_sim%avg_di
		enddo
		moments_sim%avg_di = moments_sim%avg_di/DIatriskpop
		if(sum(tot_applied) >0) then
			moments_sim%avg_hlth_acc = moments_sim%avg_hlth_acc/dble(sum(tot_applied))
		else 
			moments_sim%avg_hlth_acc = 0._dp
		endif
		!just for convenience
		forall(it=1:TT) totage(it) = sum(totage_st(it,:))
		
		!work-dif app-dif distribution by age, shock
		do it=1,(TT-1) 
			if( tot3age(it) > 0) then
				appdif_age(it) = appdif_age(it)/dble(tot3age(it))
			else
				appdif_age(it) = 0._dp
			endif
		enddo
		forall(it=1:TT-1) workdif_age(it) = workdif_age(it)/dble(totage(it)-totD(it))
		do ial=1,nal
			if(tot3al(ial) >0 ) then
				alappdif(ial) = alappdif(ial)/dble(tot3al(ial))
			else
				alappdif(ial) =0._dp
			endif
		enddo
		do ial=1,nal
			if(total(ial)>0) then
				alworkdif(ial) = alworkdif(ial)/dble(total(ial))
				!disability distribution by shock and shock,age
				alworkdif(ial) = alworkdif(ial)/dble(total(ial))
				alD(ial) = dble(alD(ial))/dble(total(ial) + alD(ial))
				do it=1,TT-1
					if(totage(it)>0) alD_age(ial,it) = alD_age(ial,it)/dble(total(ial))/dble(totage(it))
				enddo
			endif
		enddo
		! asset distribution by age, time and disability status
		do it=1,TT
			if( it<TT .and. totage(it)>0) then
				moments_sim%di_rate(it) = dble(totD(it))/dble(totage(it))
				moments_sim%work_rate(it) = dble(totW(it))/dble(totage(it))
			endif
			if(totage(it)>0) a_age(it) = a_age(it)/dble(totage(it))
		enddo
		
		! status distribution by age
		do st=1,Tsim
				if( sum(status_Nt(:,st))>0._dp ) status_Nt(:,st)= status_Nt(:,st)/sum(status_Nt(:,st))
				if( sum(totage_st(:,st)) >0 ) a_t(st) = a_t(st)/dble(sum(totage_st(:,st)))
		enddo
		
		do it=1,TT-1
			if(tot_applied(it)>0) moments_sim%hlth_acc_rt(it) = moments_sim%hlth_acc_rt(it)/dble(tot_applied(it))
		enddo

		napp_t = 0._dp
		ninsur_app = 0._dp
		moments_sim%init_di = 0._dp
		moments_sim%init_hlth_acc = 0._dp
		do i=1,Nsim
			dicont_hr = 0._dp
			do it=1,(init_yrs*itlen)
				if( hst%status_hist(i,it)<5 .and. hst%status_hist(i,it)>0 .and. shk%age_hist(i,it)>0) then
					
					! latent value of an application
					if(hst%status_hist(i,it) == 3) then
						if(hst%app_dif_hist(i,it)>(-100.) .and. hst%app_dif_hist(i,it)<100.) then
							dicont_hr = dexp(smthELPM*hst%app_dif_hist(i,it))/(1._dp+dexp(smthELPM*hst%app_dif_hist(i,it)))
							dicont_hr = dicont_hr*2._dp-1._dp  !norm it from (.5,1) to (0,1)
						!	moments_sim%init_di= moments_sim%init_di+ hst%di_prob_hist(i,it)*dexp(smthELPM*hst%app_dif_hist(i,it))/(1._dp+dexp(smthELPM*hst%app_dif_hist(i,it)))
						endif
						
						if( hst%app_dif_hist(i,it) >=0 ) then
							napp_t = napp_t+1._dp
							if(hst%hlthprob_hist(i,it)>0)  moments_sim%init_hlth_acc = moments_sim%init_hlth_acc+ hst%hlthprob_hist(i,it)/(hst%di_prob_hist(i,it))
						endif
					endif
					
					!if get DI then add the latent value when applied
					if(hst%status_hist(i,it) == 4 ) then 
						if(hst%status_hist(i,it) == 4 .and. (it==1 .or. dicont_hr==0._dp)) then
							moments_sim%init_di= moments_sim%init_di+1._dp
						endif
						if( it>1 ) then
							moments_sim%init_di= moments_sim%init_di+dicont_hr
						endif
						ninsur_app = 1._dp + ninsur_app
					elseif( hst%status_hist(i,it) == 3 ) then
						if( it>1 ) then
							moments_sim%init_di= moments_sim%init_di+dicont_hr*hst%di_prob_hist(i,it)
						endif
					endif
				endif
			enddo
		enddo
		if(ninsur_app>0._dp) then
			moments_sim%init_di= moments_sim%init_di/ninsur_app
		else
			moments_sim%init_di= 0._dp
		endif
		if(napp_t > 0._dp) then
			moments_sim%init_hlth_acc= moments_sim%init_hlth_acc/napp_t
		else
			moments_sim%init_hlth_acc= 1._dp
		endif

		if(print_lev >= 2) then
			call veci2csv(totst,"pop_st.csv")
			call vec2csv(a_age,"a_age"//trim(caselabel)//".csv")
			call vec2csv(a_t,"a_t"//trim(caselabel)//".csv")
			call vec2csv(moments_sim%di_rate,"di_age"//trim(caselabel)//".csv")
			call vec2csv(appdif_age, "appdif_age"//trim(caselabel)//".csv")
			call vec2csv(moments_sim%work_rate,"work_age"//trim(caselabel)//".csv")
			call vec2csv(workdif_age, "workdif_age"//trim(caselabel)//".csv")
			call vec2csv(alD,"alD"//trim(caselabel)//".csv")
			call mat2csv(alD_age,"alD_age"//trim(caselabel)//".csv")
			call mat2csv(status_Nt,"status_Nt"//trim(caselabel)//".csv")
			call vec2csv(moments_sim%hlth_acc_rt,"hlth_acc_rt"//trim(caselabel)//".csv")
		endif

	end subroutine moments_compute


end module model_data

!**************************************************************************************************************!
!**************************************************************************************************************!
!						Solve the model						       !
!**************************************************************************************************************!
!**************************************************************************************************************!

module sol_val

	use V0para
	use helper_funs
! module with subroutines to solve the model and simulate data from it 

	implicit none

	integer ::  Vevals
	
	contains

	subroutine maxVR(id,ie,ia, VR0, iaa0, iaaA, apol,Vout)
		integer, intent(in) :: id,ie,ia
		integer, intent(in) :: iaa0, iaaA 
		integer, intent(out) :: apol
		real(dp), intent(out) :: Vout
		real(dp), intent(in) :: VR0(:,:,:)
		real(dp) :: Vtest1,Vtest2,chere, Vc1
		integer :: iaa, iw
		

		iw=1
		Vtest1 = -1e6
		apol = iaa0
		do iaa=iaa0,iaaA
			Vevals = Vevals +1
			chere = SSret(egrid(ie))+ R*agrid(ia) - agrid(iaa)
			if( chere .gt. 0.) then !ensure positive consumption
				Vc1 = beta*ptau(TT)*VR0(id,ie,iaa)
				Vtest2 = util(chere ,id,iw) + Vc1

				if(Vtest2 > Vtest1  .or. iaa .eq. iaa0 ) then !always replace on the first loop
					Vtest1 = Vtest2
					apol = iaa
				elseif( simp_concav .eqv. .true. ) then ! imposing concavity
					exit
				endif
			else!saved too much and negative consumtion
				exit
			endif
		enddo
		Vout = Vtest1
	end subroutine maxVR

	subroutine maxVD(id,ie,ia,it, VD0, iaa0, iaaA, apol,Vout)
		integer, intent(in) :: id,ie,ia,it
		integer, intent(in) :: iaa0, iaaA 
		integer, intent(out) :: apol
		real(dp), intent(out) :: Vout
		real(dp), intent(in) :: VD0(:,:,:,:)
		real(dp) :: Vc1,chere,Vtest1,Vtest2,ein
		integer :: iw, iaa

		iw = 1 ! don't work
		Vc1 = beta*((1-ptau(it))*VD0(id,ie,iaa0,it+1)+ptau(it)*VD0(id,ie,iaa0,it))
		ein = egrid(ie)
		chere = SSDI(ein+R*agrid(ia)-agrid(iaa0))

		Vtest1 = -1e6
		apol = iaa0
		!Find Policy
		do iaa=iaa0,iaaA
			chere = SSDI(egrid(ie))+R*agrid(ia)-agrid(iaa)
			if(chere >0.) then
				Vc1 = beta*((1-ptau(it))*VD0(id,ie,iaa,it+1) + ptau(it)*VD0(id,ie,iaa,it))

				Vtest2 = util(chere,id,iw)+ Vc1
				if(Vtest2>Vtest1) then
					Vtest1 = Vtest2
					apol = iaa
				elseif(simp_concav .eqv. .true.) then
					exit
				endif
			else
				exit
			endif
		enddo	!iaa
		Vout = Vtest1
	end subroutine maxVD

	subroutine maxVU(il,itr,idi,ial,id,ie,ia,iz,it, VU0,VN0,V0,iaa0,iaaA,apol,Vout)
		integer, intent(in) :: il,itr,idi,ial,id,ie,ia,iz,it
		integer, intent(in) :: iaa0, iaaA 
		integer, intent(out) :: apol
		real(dp), intent(out) :: Vout
		real(dp), intent(in) :: VN0(:,:,:,:,:,:,:),V0(:,:,:,:,:,:,:),VU0(:,:,:,:,:,:,:)
		real(dp) :: Vc1,chere,Vtest1,Vtest2
		integer :: iw, iaa,ialal,izz,idd

		iw = 1 ! don't work
		Vtest1 = -1e6 ! just a very bad number, does not really matter
		apol = iaa0
		do iaa=iaa0,iaaA
			chere = UI(egrid(ie)) + R*agrid(ia)-agrid(iaa)
			if(chere>0.) then 
				Vtest2 = 0. !Continuation value if don't go on disability
				do izz = 1,nz	 !Loop over z'
				do ialal = ialL,nal !Loop over alpha_i'
				do idd = 1,nd
					if(ial > ialUn) then !unemp by choice
						Vc1 = (1._dp-ptau(it))*(pphi*VN0((il-1)*ntr+itr,(idi-1)*nal+ialal,idd,ie,iaa,izz,it+1) &
							& 	            +(1-pphi)*V0((il-1)*ntr+itr,(idi-1)*nal+ialal,idd,ie,iaa,izz,it+1) )  !Age and might go LTU
						Vc1 = ptau(it)*(pphi*     VN0((il-1)*ntr+itr,(idi-1)*nal+ialal,idd,ie,iaa,izz,it) & 
							&	      +(1-pphi)*   V0((il-1)*ntr+itr,(idi-1)*nal+ialal,idd,ie,iaa,izz,it) ) + Vc1    !Don't age, maybe LTU
					else !unemployed exogenously
						Vc1 = (1._dp-ptau(it))*(pphi*     VN0((il-1)*ntr+itr,(idi-1)*nal+ialUn,idd,ie,iaa,izz,it+1) &
							& 	+(1-pphi)*( fndgrid(il,iz)*V0((il-1)*ntr+itr,(idi-1)*nal+ialal,idd,ie,iaa,izz,it+1) +&
									 (1.- fndgrid(il,iz))*VU0((il-1)*ntr+itr,(idi-1)*nal+ialUn,idd,ie,iaa,izz,it+1)  ) )  !Age and might go LTU

						Vc1 = ptau(it)*(pphi*             VN0((il-1)*ntr+itr,(idi-1)*nal+ialUn,idd,ie,iaa,izz,it) & 
							  & +(1-pphi)*( fndgrid(il,iz)*V0((il-1)*ntr+itr,(idi-1)*nal+ialal,idd,ie,iaa,izz,it) +&
							  &		  (1.-fndgrid(il,iz))*VU0((il-1)*ntr+itr,(idi-1)*nal+ialUn,idd,ie,iaa,izz,it) ) ) + Vc1    !Don't age, maybe LTU
					endif

					!Vc1 = (1.-fndgrid(il,iz))*Vc1 + fndgrid(il,iz)*V0((ij-1)*ntr+itr,(idi-1)*nal+ialal,id,ie,iaa,izz,it)
					Vtest2 = Vtest2 + beta*piz(iz,izz)*pialf(ial,ialal)*pid(id,idd,idi,it) *Vc1  !Probability of alpha_i X z_i draw 
				enddo
				enddo
				enddo
				Vtest2 = Vtest2 + util(chere,id,iw)
				if(Vtest2>Vtest1 .or. iaa .eq. iaa0) then !first value or optimal
					apol = iaa! set the policy
					Vtest1 = Vtest2
				elseif( simp_concav .eqv. .true. ) then
					exit
				endif
			else
				exit
			endif
		enddo
		Vout = Vtest1
	end subroutine maxVU

	subroutine maxVN(il,itr,idi,ial,id,ie,ia,iz,it, VN0, VD0, V0,wagehere, iaa0,iaaA,apol,gapp_pol,gapp_dif,Vout  )
		integer, intent(in) :: il,itr,idi,ial,id,ie,ia,iz,it
		integer, intent(in) :: iaa0, iaaA 
		integer, intent(out) :: apol,gapp_pol
		real(dp), intent(out) :: gapp_dif
		real(dp), intent(out) :: Vout
		real(dp), intent(in) :: VN0(:,:,:,:,:,:,:),VD0(:,:,:,:),V0(:,:,:,:,:,:,:),wagehere
		real(dp) :: Vc1,chere,Vtest1,Vtest2,Vapp,VNapp,smthV, VNhr, VDhr, maxVNV0, minvalVD,minvalVN, xihr,nuhr
		integer :: iw, iaa,ialal,izz,aapp,aNapp, ialalhr,idd

		iw = 1 ! not working
		!*******************************************
		!**************Value if do not apply for DI
		
		Vtest1 = -1e6
		apol = iaa0
		do iaa = iaa0,iaaA
			chere = b+R*agrid(ia)-agrid(iaa)
			if(chere >0.) then
				Vtest2 = 0.
				!Continuation if do not apply for DI
				do izz = 1,nz	 !Loop over z'
				do ialal = ialL,nal !Loop over alpha_i'
				do idd = 1,nd
					if(ial == ialUn) ialalhr = ialUn
					if(ial > ialUn)  ialalhr = ialal
					VNhr    =   	VN0((il-1)*ntr+itr,(idi-1)*nal +ialalhr,idd,ie,iaa,izz,it+1)
					maxVNV0 = max(   V0((il-1)*ntr+itr,(idi-1)*nal +ialal  ,idd,ie,iaa,izz,it+1),VNhr)

					Vc1 = (1-ptau(it))*( (1-lrho*fndgrid(il,iz) )*VNhr +lrho*fndgrid(il,iz)*maxVNV0 ) !Age and might go on DI

					VNhr    =   	VN0((il-1)*ntr+itr,(idi-1)*nal +ialalhr,idd,ie,iaa,izz,it)
					maxVNV0 = max(   V0((il-1)*ntr+itr,(idi-1)*nal +ialal  ,idd,ie,iaa,izz,it),VNhr)

					Vc1 = Vc1+ptau(it)*((1-lrho*fndgrid(il,iz))*VNhr +lrho*fndgrid(il,iz)*maxVNV0)     !Don't age, might go on DI
					
					Vtest2 = Vtest2 + beta*piz(iz,izz)*pialf(ial,ialal)*pid(id,idd,idi,it) *Vc1 
				enddo
				enddo
				enddo
				Vtest2 = Vtest2 + util(chere,id,iw)
				
				if( Vtest2 > Vtest1 .or. iaa .eq. iaa0) then
					apol = iaa 
					Vtest1 = Vtest2
				elseif(simp_concav .eqv. .true.) then
					exit
				endif
			!elseif(iaa .eq. iaa0 .and. Vtest1 <= -1e5 .and. apol .eq. iaa0) then
			!	iaa = 1 !started too much saving, go back towards zero
			else
				exit
			endif
		enddo !iaa
		Vnapp = Vtest1 					
		aNapp = apol !agrid(apol)
		if((Vnapp <-1e5) .and. (verbose >0)) then
			write(*,*) "ruh roh!"
			write(*,*) "Vnapp, aNapp: ", Vnapp, aNapp
			write(*,*) "VD: ",id,ie,iaa,it
			write(*,*) "VN: ",il,itr,idi,ial,id,ie,ia,iz,it
		endif
	
		!**********Value if apply for DI 

		xihr = xifun(id,trgrid(itr),it)
		nuhr = nu
		if(it== TT-1) nuhr = nu*(ptau(it)) !only pay nu for non-retired state
		minvalVD = minval(VD0)
		minvalVN = minval(VN0((il-1)*ntr+itr,((idi-1)*nal+1):(idi*nal),:,:,:,:,it))
		Vtest1 = -1e6
		apol = iaa0
		do iaa = iaa0,iaaA
			chere = b+R*agrid(ia)-agrid(iaa)
			if(chere >0.) then
				Vtest2 = 0.
				!Continuation if apply for DI
				do izz = 1,nz	 !Loop over z'
				do ialal = ialL,nal !Loop over alpha_i'
				do idd = 1,nd
					if(ial == ialUn) ialalhr = ialUn
					if(ial > ialUn)  ialalhr = ialal					
					VNhr    =   	VN0((il-1)*ntr+itr,(idi-1)*nal +ialalhr,idd,ie,iaa,izz,it+1)				
					maxVNV0 = max(	 V0((il-1)*ntr+itr,(idi-1)*nal +ialal  ,idd,ie,iaa,izz,it+1), VNhr)

					VDhr    = max(VD0(idd,ie,iaa,it+1),VNhr)
					Vc1 =   (1-ptau(it))*(1-xihr)*( (1-lrho*fndgrid(il,iz) )*VNhr +lrho*fndgrid(il,iz)*maxVNV0 )&
						& + (1-ptau(it))*xihr    *VDhr !Age and might go on DI

					VNhr    =   	VN0((il-1)*ntr+itr,(idi-1)*nal +ialalhr,idd,ie,iaa,izz,it)
					maxVNV0 = max(	 V0((il-1)*ntr+itr,(idi-1)*nal +ialal  ,idd,ie,iaa,izz,it),VNhr)

					VDhr    = max(VD0(idd,ie,iaa,it),VNhr)
					Vc1 = Vc1 +	    ptau(it)*(1-xihr)*( (1-lrho*fndgrid(il,iz))*VNhr +lrho*fndgrid(il,iz)*maxVNV0 ) &
						&     + 	ptau(it)*xihr    * VDhr     !Don't age, might go on DI		

			!		if(it<TT-1) Vc1 = Vc1/ptau(it)
					Vtest2 = Vtest2 + beta*piz(iz,izz)*pialf(ial,ialal) *pid(id,idd,idi,it) *Vc1 
				enddo
				enddo
				enddo
				Vtest2 = util(chere,id,iw) + Vtest2 &
					& - nuhr
				if (Vtest2>Vtest1  .or. iaa .eq. iaa0) then	
					apol = iaa
					Vtest1 = Vtest2
				elseif(simp_concav .eqv. .true.) then
					exit
				endif

			else
				exit
			endif
		enddo !iaa
		Vapp = Vtest1
		aapp = apol !agrid(apol)					

		if(Vapp <-1e5) then
			write(*,*) "ruh roh!"
			write(*,*) "Vapp, aapp: ", Vapp, aapp
			write(*,*) "VD: ",id,ie,iaa,it
			write(*,*) "VN: ",il,itr,idi,ialal,id,ie,iaa,izz,it
		endif

		!******************************************************
		!***************** Discrete choice for application
		!smthV = dexp(smthV0param*Vnapp)/( dexp(smthV0param*Vnapp) +dexp(smthV0param*Vapp) )
		!if( smthV .lt. 1e-5 .or. smthV .gt. 0.999999 .or. isnan(smthV)) then
			if( Vapp > Vnapp ) smthV =0.
			if(Vnapp > Vapp  ) smthV =1._dp
		!endif
		if (Vapp > Vnapp) then
			apol = aapp
			gapp_pol = 1
		else !Don't apply
			apol = aNapp
			gapp_pol = 0
		endif

		gapp_dif = Vapp - Vnapp
		if(verbose .gt. 4) print *, Vapp - Vnapp
		if((it == 1) .and. (ineligNoNu .eqv. .true.)) then
			Vout = smthV*Vnapp + (1._dp - smthV)*(eligY*Vapp + (1._dp- eligY)*Vnapp)
		else
			Vout = smthV*Vnapp + (1._dp - smthV)*Vapp
		endif

	end subroutine maxVN

	subroutine maxVW(il,itr,idi,ial,id,ie,ia,iz,it, VU, V0,wagehere,iee1,iee2,iee1wt,iaa0,iaaA,apol,gwork_pol,gwork_dif,Vout ,VWout )
		integer, intent(in) :: il,itr,idi,ial,id,ie,ia,iz,it
		integer, intent(in) :: iaa0, iaaA,iee1,iee2
		real(dp), intent(in) :: iee1wt,wagehere
		integer, intent(out) :: apol,gwork_pol
		real(dp), intent(out) :: gwork_dif
		real(dp), intent(out) :: Vout, VWout
		real(dp), intent(in) :: VU(:,:,:,:,:,:,:),V0(:,:,:,:,:,:,:)
		real(dp) :: Vc1,utilhere,chere,Vtest1,Vtest2,VWhere,VUhere,smthV, vL, vH, uL, uH
		integer :: iw, iaa,ialal,izz,idd

		iw = 2 ! working
		Vtest1= -1.e6_dp ! just to initialize, does not matter
		apol = iaa0
		
		!Find saving Policy
		do iaa=iaa0,iaaA
			!Continuation value if don't go on disability
			chere = wagehere+R*agrid(ia)-agrid(iaa)
			if (chere >0.) then
				Vc1 = 0.
				do izz  = 1,nz	 !Loop over z'
				do ialal = ialL,nal  !Loop over alpha_i'
				do idd  = 1,nd	 !Loop over d'
					!Linearly interpolating on e'
					vL = (1-ptau(it))*V0((il-1)*ntr+itr,(idi-1)*nal+ialal,idd,iee1,iaa,izz,it+1) & 
						& +ptau(it)  *V0((il-1)*ntr+itr,(idi-1)*nal+ialal,idd,iee1,iaa,izz,it)
					vH = (1-ptau(it))*V0((il-1)*ntr+itr,(idi-1)*nal+ialal,idd,iee2,iaa,izz,it+1) & 
						& +ptau(it)  *V0((il-1)*ntr+itr,(idi-1)*nal+ialal,idd,iee2,iaa,izz,it)
					!if become unemployed here - 
					uL = (1-ptau(it))*VU((il-1)*ntr+itr,(idi-1)*nal+ialUn,idd,iee1,iaa,izz,it+1) & 
						& +ptau(it)  *VU((il-1)*ntr+itr,(idi-1)*nal+ialUn,idd,iee1,iaa,izz,it)
					uH = (1-ptau(it))*VU((il-1)*ntr+itr,(idi-1)*nal+ialUn,idd,iee2,iaa,izz,it+1) & 
						& +ptau(it)  *VU((il-1)*ntr+itr,(idi-1)*nal+ialUn,idd,iee2,iaa,izz,it)
					!uL = VU((il-1)*ntr+itr,(idi-1)*nal+ialUn,idd,iee1,iaa,izz,it)
					!uH = VU((il-1)*ntr+itr,(idi-1)*nal+ialUn,idd,iee2,iaa,izz,it)	
						
					Vc1 = piz(iz,izz)*pialf(ial,ialal)*pid(id,idd,idi,it) &
						& * (  (1.-sepgrid(il,iz))*(vH*(1._dp - iee1wt) + vL*iee1wt) &
							+  sepgrid(il,iz)*     (uH*(1._dp - iee1wt) + uL*iee1wt) ) &
						& + Vc1
				enddo
				enddo
				enddo
				utilhere = util(chere,id,iw)
				Vtest2 = utilhere + beta*Vc1 ! flow utility

				if (Vtest2>Vtest1 .or. iaa .eq. iaa0 ) then  !always replace on the first, or best
					Vtest1 = Vtest2
					apol = iaa
				elseif (simp_concav .eqv. .true.) then
					! if we are imposing concavity
					exit
				endif
			else 
				exit
			endif
		enddo	!iaa

		VWhere = Vtest1
		VUhere = VU((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it)
		
		!------------------------------------------------!
		!Calculate V with solved vals of VW and VU -- i.e. can quit into unemployment
		!------------------------------------------------!
		
		if (VWhere>VUhere) then
			gwork_pol = 1
		else
			gwork_pol = 0
		endif
		!smthV = dexp( smthV0param *VWhere  ) &
		!	& /( dexp(smthV0param * VWhere) + dexp(smthV0param * VUhere ) )
		!if (smthV <1e-5 .or. smthV>.999999 .or. isnan(smthV) ) then
			if(VWhere > VUhere)	smthV = 1._dp 
			if(VWhere < VUhere)	smthV = 0. 							
		!endif
		Vout = smthV*VWhere + (1._dp-smthV)*VUhere
		
		gwork_dif = VWhere - VUhere
		VWout = VWhere
		
	end subroutine maxVW

	subroutine sol(val_funs, pol_funs)

		implicit none
	
		type(val_struct), intent(inout), target :: val_funs
		type(pol_struct), intent(inout), target :: pol_funs	

	!************************************************************************************************!
	! Counters and Indicies
	!************************************************************************************************!

		integer  :: i, j, ia, ie, id, it, ga,gw, anapp,aapp, apol, itr, ial, il , idi,  &
			    iee1, iee2, iz, iw,wo, iter,npara,ipara, iaa_k,iaa0,iaaA,iaN, iter_timeout
		integer, dimension(5) :: maxer_i

		integer :: aa_l(na), aa_u(na), ia_o(na),aa_m(na)

		logical :: ptrsucces
		!************************************************************************************************!
		! Value Functions- Stack z-risk j and indiv. exposure beta_i
		!************************************************************************************************!
		real(dp)  	  	:: Vtest1, maxer_v, smthV,smthV0param, wagehere, iee1wt, gadif,gwdif
		
		real(dp), allocatable	:: maxer(:,:,:,:,:)
		real(dp), allocatable :: VR0(:,:,:), &			!Retirement
					VD0(:,:,:,:), &			!Disabled
					VN0(:,:,:,:,:,:,:), &	!Long-term Unemployed
					VW0(:,:,:,:,:,:,:), &	!Working
					VU0(:,:,:,:,:,:,:), &	!Unemployed
					V0(:,:,:,:,:,:,:)	!Participant
				
		real(dp), pointer ::	VR(:,:,:), &			!Retirement
					VD(:,:,:,:), &			!Disabled
					VN(:,:,:,:,:,:,:), &	!Long-term Unemployed
					VW(:,:,:,:,:,:,:), &	!Working
					VU(:,:,:,:,:,:,:), &	!Unemployed
					V(:,:,:,:,:,:,:)	!Participant
	
		real(dp), pointer ::	gapp_dif(:,:,:,:,:,:,:), gwork_dif(:,:,:,:,:,:,:) ! latent value of work/apply
	
		integer, pointer ::	aR(:,:,:), aD(:,:,:,:), aU(:,:,:,:,:,:,:), &
					aN(:,:,:,:,:,:,:), aW(:,:,:,:,:,:,:)
		integer, pointer ::	gapp(:,:,:,:,:,:,:), &
					gwork(:,:,:,:,:,:,:)
	
		!************************************************************************************************!
		! Other
		!************************************************************************************************!
			real(dp)	:: junk,summer, eprime, emin, emax, VWhere, V_m(na)
		!************************************************************************************************!
		
		!************************************************************************************************!
		! Allocate phat matrices
		!************************************************************************************************!
		! (disability extent, earn hist, assets)
		allocate(VR0(nd,ne,na))
		allocate(VD0(nd,ne,na,TT))
		allocate(VN0(nl*ntr,ndi*nal,nd,ne,na,nz,TT))
		allocate(VU0(nl*ntr,ndi*nal,nd,ne,na,nz,TT))
		allocate(VW0(nl*ntr,ndi*nal,nd,ne,na,nz,TT))
		allocate(V0(nl*ntr,ndi*nal,nd,ne,na,nz,TT))
		! there must be a way to use pointers, but it doesn't seem to work
		VR => val_funs%VR
		aR => pol_funs%aR
		VD => val_funs%VD
		aD => pol_funs%aD
		VN => val_funs%VN
		VU => val_funs%VU
		VW => val_funs%VW
		V =>  val_funs%V
		aN => pol_funs%aN
		aW => pol_funs%aW
		aU => pol_funs%aU
		gwork => pol_funs%gwork
		gapp => pol_funs%gapp

		gapp_dif => pol_funs%gapp_dif
		gwork_dif => pol_funs%gwork_dif

		allocate(maxer(na,nz,ne,nd,nal))
		emin = minval(egrid)
		emax = maxval(egrid)

		ptrsucces = associated(VR,val_funs%VR)
		
		simp_concav = .false.
		!************************************************************************************************!
		! Caculate things that are independent of occupation/person type
		!	1) Value of Retired:  VR(d,e,a)
		!	2) Value of Disabled: VD(d,e,a)
		
	!1) Calculate Value of Retired: VR(d,e,a)
		!d in{1,2,3}  : disability extent
		!e inR+       :	earnings index
		!a inR+	      : asset holdings
		
		Vevals = 0
		!VFI with good guess
		!Initialize
		iw=1
		do id=1,nd
		do ie=1,ne
		do ia=1,na
			VR0(id,ie,ia) = util(SSret(egrid(ie))+R*agrid(ia),id,iw)* (1._dp/(1._dp-beta*ptau(TT)))
		enddo
		enddo
		enddo
		if(print_lev >3) then
			i = 1
			call vec2csv(VR0(i,i,:),"VR0.csv",0)
		endif		
		iter = 1
!		simp_concav = .true. ! use simple concavity here
		do while (iter<=maxiter)
			summer = 0
			do id =1,nd
		  	do ie =1,ne

				iaN =0
				ia = 1
				iaa0 = 1
				iaaA = na
				call maxVR(id,ie,ia, VR0, iaa0, iaaA, apol,Vtest1)
				VR(id,ie,ia) = Vtest1
				aR(id,ie,ia) = apol !agrid(apol)
				iaN = iaN+1
				ia_o(iaN) = ia
					
				ia = na
				iaa0 = aR(id,ie,1)
				iaaA = na
				call maxVR(id,ie,ia, VR0, iaa0, iaaA, apol,Vtest1)
				VR(id,ie,ia) = Vtest1
				aR(id,ie,ia) = apol !agrid(apol)
				iaN = iaN+1
				ia_o(iaN) = ia
					

				iaa_k = 1
				aa_l(iaa_k) = 1
				aa_u(iaa_k) = na

				!main loop (step 1 of Gordon & Qiu completed)
				outerVR: do
					!Expand list (step 2 of Gordon & Qiu)
					do
						if(aa_u(iaa_k) == aa_l(iaa_k)+1) exit
						iaa_k = iaa_k+1
						aa_l(iaa_k) = aa_l(iaa_k-1)
						aa_u(iaa_k) = (aa_l(iaa_k-1)+aa_u(iaa_k-1))/2
						!search given ia from iaa0 to iaaA
						ia = aa_u(iaa_k)
						iaa0 = aR(id,ie, aa_l(iaa_k-1) )
						iaaA = aR(id,ie, aa_u(iaa_k-1) )
						call maxVR(id,ie,ia, VR0, iaa0, iaaA, apol,Vtest1)
						VR(id,ie,ia) = Vtest1
						aR(id,ie,ia) = apol
						iaN = iaN+1
						ia_o(iaN) = ia
					
					enddo
					! Move to a higher interval or stop (step 3 of Gordon & Qiu)
					do
						if(iaa_k==1) exit outerVR
						if( aa_u(iaa_k)/= aa_u(iaa_k - 1) ) exit
						iaa_k = iaa_k -1
					end do
					! more to the right subinterval
					aa_l(iaa_k) = aa_u(iaa_k)
					aa_u(iaa_k) = aa_u(iaa_k-1)
				end do outerVR
				
				do ia=1,na
					summer = summer+ (VR(id,ie,ia)-VR0(id,ie,ia))**2
				enddo
				VR0(id,ie,:) = VR(id,ie,:)
			enddo !ie
			enddo !id
			if (summer < Vtol) then
				exit	!Converged				
			else
				iter=iter+1
				if(print_lev >3) then
					i = 1
					call veci2csv(aR(i,i,:),"aR.csv",0)
					call vec2csv(VR(i,i,:),"VR.csv",0)
				endif
			endif
		enddo ! iteration iter

		if(summer >= Vtol) then
			print *, "VR did not converge"
		endif 

		i = 1
		do id =2,nd
		do ie =1,ne
		do ia =1,na
			VR(id,ie,ia) = VR(i,ie,ia)*(dexp(theta*dble(id-1)))**(1-gam)
			aR(id,ie,ia) = aR(i,ie,ia)
		enddo
		enddo
		enddo

		if (print_lev > 2) then
			wo =0
			do id=1,nd
			do ie=1,ne
				call veci2csv(aR(i,i,:),"aR.csv",wo)
				call vec2csv(VR(i,i,:),"VR.csv",wo)
				if(wo .eq. 0) wo = 1
			enddo
			enddo
		endif

		!----------------------------------------------------------!
		!Set value at t=TT to be VR in all other V-functions
		!----------------------------------------------------------!
		VD(:,:,:,TT) = VR
		VD0(:,:,:,TT) = VR
		VD0(:,:,:,TT-1) = VD0(:,:,:,TT) ! this is necessary for initialization given stochastic aging

	!----------------------------------------------------------------!
	!2) Calculate Value of Disabled: VD(d,e,a,t)	 
		!d in{1,2,3}  	   :disability extent
		!e inR+       	   :earnings index
		!a inR+	      	   :asset holdings
		!t in[1,2...TT-1]  :age

		!simp_concav = .true.
		npara = nd*ne
		!Work backwards from TT
		do it = TT-1,1,-1
			!Guess will be value at t+1
			VD0(:,:,:,it) = VD(:,:,:,it+1)
			iw = 1 ! not working

			do id =1,nd 

				if(print_lev >3) then
					call mat2csv(VD0(id,:,:,it),"VD0.csv",0)
				endif
				!Loop over earnings index
				do ie=1,ne
					!Loop to find V(..,it) as fixed point
					iter=1
					do while (iter<=maxiter)
						summer = 0

						iaN = 0
						ia = 1
						iaa0 = 1
						iaaA = na
						call maxVD(id,ie,ia,it, VD0, iaa0, iaaA, apol,Vtest1)
						VD(id,ie,ia,it) = Vtest1
						aD(id,ie,ia,it) = apol !agrid(apol)
						iaN = iaN+1
						ia_o(iaN) = ia
					

						ia = na
						iaa0 = aD(id,ie,1,it)
						iaaA = na
						call maxVD(id,ie,ia,it, VD0, iaa0, iaaA, apol,Vtest1)
						VD(id,ie,ia,it) = Vtest1
						aD(id,ie,ia,it) = apol !agrid(apol)
						iaN = iaN+1
						ia_o(iaN) = ia

					
						iaa_k = 1
						aa_l(iaa_k) = 1
						aa_u(iaa_k) = na

						!main loop (step 1 of Gordon & Qiu completed)
						outerVD: do
							!Expand list (step 2 of Gordon & Qiu)
							do
								if(aa_u(iaa_k) == aa_l(iaa_k)+1) exit
								iaa_k = iaa_k+1
								aa_l(iaa_k) = aa_l(iaa_k-1)
								aa_u(iaa_k) = (aa_l(iaa_k-1)+aa_u(iaa_k-1))/2
								!search given ia from iaa0 to iaaA
								ia = aa_u(iaa_k)
								iaa0 = aD(id,ie, aa_l(iaa_k-1),it)
								iaaA = aD(id,ie, aa_u(iaa_k-1),it)
								call maxVD(id,ie,ia,it, VD0, iaa0, iaaA, apol,Vtest1)
								VD(id,ie,ia,it) = Vtest1
								aD(id,ie,ia,it) = apol
								iaN = iaN+1
								ia_o(iaN) = ia
					
							enddo
							! Move to a higher interval or stop (step 3 of Gordon & Qiu)
							do
								if(iaa_k==1) exit outerVD
								if( aa_u(iaa_k)/= aa_u(iaa_k - 1) ) exit
								iaa_k = iaa_k -1
							end do
							! more to the right subinterval
							aa_l(iaa_k) = aa_u(iaa_k)
							aa_u(iaa_k) = aa_u(iaa_k-1)
						end do outerVD
						
						do ia=1,na
							summer = summer+ (VD(id,ie,ia,it)-VD0(id,ie,ia,it))**2
						enddo

						if(print_lev >3) then
							wo =0
							call veci2csv(aD(id,ie,:,it),"aD.csv",wo)
							call vec2csv(VD(id,ie,:,it),"VD.csv",wo)
						endif
						if (summer < Vtol) then
							exit	!Converged
						endif
						VD0(id,ie,:,it) = VD(id,ie,:,it)	!New guess
						iter=iter+1

					enddo	!iter: V-iter loop
				enddo	!ie		

			enddo !id = 1,nd
		enddo	!t loop, going backwards



		VD0 = VD
		if (print_lev >= 2) then
			wo =0 
			do id =1,nd
			do ie =1,ne
				call mati2csv(aD(id,ie,:,:),"aD.csv",wo)
				call mat2csv(VD(id,ie,:,:),"VD.csv",wo)
				if(wo == 0) wo =1
			enddo
			enddo
		endif


	!************************************************************************************************!
	!3) Calculate V= max(VW,VN); requires calculating VW and VN

	! initialize

		do id=1,nd
		do ie=1,ne
		do ia=1,na
			VW (:,:,id,ie,ia,:,TT) = VR(id,ie,ia)
			VW0(:,:,id,ie,ia,:,TT) = VR(id,ie,ia)
			VN (:,:,id,ie,ia,:,TT) = VR(id,ie,ia)
			VN0(:,:,id,ie,ia,:,TT) = VR(id,ie,ia)
			VU (:,:,id,ie,ia,:,TT) = VR(id,ie,ia)
			VU0(:,:,id,ie,ia,:,TT) = VR(id,ie,ia)
			V  (:,:,id,ie,ia,:,TT) = VR(id,ie,ia)
			V0 (:,:,id,ie,ia,:,TT) = VR(id,ie,ia)	   
		enddo
		enddo
		enddo


		
		! Begin loop over occupations
		do il = 1,nl
		! And individual disability type
		do idi = 1,ndi

		!************************************************************************************************!
			!Work Backwards TT-1,TT-2...1!
		do it=TT-1,1,-1
			!----Initialize---!
			
			if( il==1 .and. idi>1) then
				do ial=1,nal
				do itr = 1,ntr 				
				do id =1,nd
				do ie =1,ne
				do iz =1,nz
				do ia =1,na
					
				!Guess once, then use last occupation as guess (order occupations intelligently)
				! for it = 1, should be TT-1+1 =TT -> VU,Vw,VN = VR
					VW0((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = VW0((il-1)*ntr+itr,(idi-2)*nal+ial,id,ie,ia,iz,it)  
					VU0((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = VU0((il-1)*ntr+itr,(idi-2)*nal+ial,id,ie,ia,iz,it)
					VN0((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = VN0((il-1)*ntr+itr,(idi-2)*nal +ial,id,ie,ia,iz,it)
					V0 ((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = V0 ((il-1)*ntr+itr,(idi-2)*nal+ial,id,ie,ia,iz,it)

				enddo	!ia
				enddo	!iz
				enddo	!ie
				enddo 	!id
				enddo 	!itr
				enddo	!ial
			elseif( il>1 ) then
				do ial=1,nal
				do itr = 1,ntr 
				do id =1,nd
				do ie =1,ne
				do iz =1,nz
				do ia =1,na
					
				!Guess once, then use last occupation as guess (order occupations intelligently)
				! for it = 1, should be TT-1+1 =TT -> VU,Vw,VN = VR
					VW0((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = VW0((il-2)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it)  
					VU0((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = VU0((il-2)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it)
					VN0((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = VN0((il-2)*ntr+itr,(idi-1)*nal +ial,id,ie,ia,iz,it)
					V0 ((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = V0 ((il-2)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it)

				enddo	!ia
				enddo	!iz
				enddo	!ie
				enddo 	!id
				enddo	!itr
				enddo	!ial
			else  ! should be only (il ==1 .and. idi == 1)  then
				do ial=1,nal
				do itr = 1,ntr 
				do id =1,nd
				do ie =1,ne
				do iz =1,nz
				do ia =1,na
					
				!Guess once, then use next period same occupation/beta as guess
				! for it = 1, should be TT-1+1 =TT -> VU,Vw,VN = VR
					VW0((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it)  = VW ((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it+1)
					VU0((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it)  = VU ((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it+1)
					VN0((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it)  = VN ((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it+1)
					V0 ((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it)  = VW0((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it)

				enddo	!ia
				enddo	!iz
				enddo	!ie
				enddo 	!id
				enddo	!itr
				enddo	!ial
			
			endif

			!***********************************************************************************************************
			!Loop over V=max(VU,VW)	
			iter=1
			iter_timeout = 0
			smthV0param  =1._dp ! will tighten this down
			do while (iter<=maxiter)
				maxer = 0.
				summer = 0.	!Use to calc |V-V0|<eps
				! lots f printing every 100 iterations (mod 1 because Fortran is designed by idiots using base-1 indexing)
				!if(mod(iter,3) .eq. 0) then
					simp_concav = .false.
				!else
				!	simp_concav = .true.
				!endif
			!------------------------------------------------!
			!Solve VU given guesses on VW, VN, VU and implied V
			!------------------------------------------------!
				summer = 0.
				wo = 0
				npara = nal*ntr*nd*ne*nz
			!$OMP  parallel do reduction(+:summer)&
			!$OMP& private(ial,id,ie,iz,iw,itr,apol,iaa0,iaaA,ia,ipara,Vtest1,aa_m,V_m,aa_l,aa_u,iaa_k,iaN,ia_o)
				do ipara = 1,npara
					iz = mod(ipara-1,nz)+1
					ie = mod(ipara-1,nz*ne)/nz + 1
					id = mod(ipara-1,nz*ne*nd)/(nz*ne) +1
					itr= mod(ipara-1,nz*ne*nd*ntr)/(nz*ne*nd) +1
					ial= mod(ipara-1,nz*ne*nd*ntr*nal)/(nz*ne*nd*ntr)+1

					! search over ia
						iaN =0
						ia = 1
						iaa0 = 1
						iaaA = na
						call maxVU(il,itr,idi,ial,id,ie,ia,iz,it, VU0,VN0,V0, iaa0,iaaA,apol,Vtest1)
						V_m(ia) = Vtest1
						aa_m(ia) = apol !agrid(apol)
						iaN = iaN+1
						ia_o(iaN) = ia
					
						ia = na
						iaa0 = aa_m(1)
						iaaA = na
						call maxVU(il,itr,idi,ial,id,ie,ia,iz,it, VU0,VN0,V0, iaa0,iaaA,apol,Vtest1)
						V_m(ia) = Vtest1
						aa_m(ia) = apol !agrid(apol)
						iaN = iaN+1
						ia_o(iaN) = ia
					

						iaa_k = 1
						aa_l(iaa_k) = 1
						aa_u(iaa_k) = na

						!main loop (step 1 of Gordon & Qiu completed)
						outerVU: do
							!Expand list (step 2 of Gordon & Qiu)
							do
								if(aa_u(iaa_k) == aa_l(iaa_k)+1) exit
								iaa_k = iaa_k+1
								aa_l(iaa_k) = aa_l(iaa_k-1)
								aa_u(iaa_k) = (aa_l(iaa_k-1)+aa_u(iaa_k-1))/2
								!search given ia from iaa0 to iaaA
								ia = aa_u(iaa_k)
								iaa0 = aa_m( aa_l(iaa_k-1) )
								iaaA = aa_m( aa_u(iaa_k-1) )
								call maxVU(il,itr,idi,ial,id,ie,ia,iz,it, VU0,VN0,V0, iaa0,iaaA,apol,Vtest1)
								V_m(ia) = Vtest1
								aa_m(ia) = apol !agrid(apol)
								iaN = iaN+1
								ia_o(iaN) = ia
					
							enddo
							! Move to a higher interval or stop (step 3 of Gordon & Qiu)
							do
								if(iaa_k==1) exit outerVU
								if( aa_u(iaa_k)/= aa_u(iaa_k - 1) ) exit
								iaa_k = iaa_k -1
							end do
							! more to the right subinterval
							aa_l(iaa_k) = aa_u(iaa_k)
							aa_u(iaa_k) = aa_u(iaa_k-1)
						end do outerVU
						
						aU((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,:,iz,it) = aa_m
						VU((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,:,iz,it) = V_m
							
						if((iz>nz .or. ie>ne .or. id>nd .or. ial>nal) .and. verbose > 2) then
							print *, "ipara is not working right", iz,ie,id,ial
						endif
						Vtest1 = sum( (VU((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,:,iz,it) &
							& - VU0((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,:,iz,it))**2)
						summer = Vtest1 + summer
						if(print_lev >3) then
							call veci2csv(ia_o,"ia_o_VU.csv",wo)
							if(wo == 0) wo =1
						endif
						
				enddo !ipara
			!$OMP END PARALLEL do
				!update VU0
				do ial=1,nal	!Loop over alpha (ai)
				do itr=1,ntr	!Loop over trend
				do id=1,nd	!Loop over disability index
				do ie=1,ne	!Loop over earnings index
				do iz=1,nz	!Loop over TFP
					do ia =1,na
						VU0((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = VU((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it)
					enddo	!ia
				enddo !ial <- these are not in order
				enddo !itr
				enddo !id
				enddo !ie
				enddo !iz
				if (print_lev > 3) then
					wo = 0
					itr = tri0
					do ial=1,nal	!Loop over alpha (ai)
					do id=1,nd	!Loop over disability index
					do ie=1,ne	!Loop over earnings index
					do iz=1,nz	!Loop over TFP
						call veci2csv(aU((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,:,iz,it),"aU.csv",wo)
						call vec2csv(VU((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,:,iz,it),"VU.csv",wo)
						if(wo == 0) wo = 1 
					enddo
					enddo
					enddo
					enddo
				endif


			!------------------------------------------------!
			!Solve VN given guesses on VW, VN, and implied V
			!------------------------------------------------! 
				summer = 0.
				wo = 0
				aa_u = 0
				npara = nal*ntr*nd*ne*nz
			!$OMP  parallel do reduction(+:summer)&
			!$OMP& private(ipara,ial,id,ie,iz,itr,apol,ga,gadif,ia,iaa0,iaaA,iaa_k,aa_l,aa_u,aa_m,V_m,Vtest1,wagehere,iaN,ia_o) 
				do ipara = 1,npara
					iz = mod(ipara-1,nz)+1
					ie = mod(ipara-1,nz*ne)/nz + 1
					id = mod(ipara-1,nz*ne*nd)/(nz*ne) +1
					itr= mod(ipara-1,nz*ne*nd*ntr)/(nz*ne*nd) +1
					ial= mod(ipara-1,nz*ne*nd*ntr*nal)/(nz*ne*nd*ntr)+1

					wagehere = wage(trgrid(itr),alfgrid(ial),id,zgrid(iz,1),it) !<-zgrid should be parameterized by ij!
					!----------------------------------------------------------------
					!Loop over current state: assets
					iaN=0
					ia = 1
					iaa0 = 1
					iaaA = na
					call maxVN(il,itr,idi,ial,id,ie,ia,iz,it, VN0, VD0,V0,wagehere,iaa0,iaaA,apol,ga,gadif,Vtest1)
					aa_m(ia) = apol
					V_m(ia) = Vtest1
					gapp((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = ga
					gapp_dif((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = gadif
					iaN = iaN+1
					ia_o(iaN) = ia
					

					ia = na
					iaa0 = aa_m(1)
					iaaA = na
					call maxVN(il,itr,idi,ial,id,ie,ia,iz,it, VN0, VD0,V0,wagehere,iaa0,iaaA,apol,ga,gadif,Vtest1)
					V_m(ia) = Vtest1
					aa_m(ia) = apol !agrid(apol)
					gapp((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = ga
					gapp_dif((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = gadif
					iaN = iaN+1
					ia_o(iaN) = ia
					

					iaa_k = 1
					aa_l(iaa_k) = 1
					aa_u(iaa_k) = na

					outerVN: do
						do
							if(aa_u(iaa_k) == aa_l(iaa_k)+1) exit
							iaa_k = iaa_k+1
							aa_l(iaa_k) = aa_l(iaa_k-1)
							aa_u(iaa_k) = (aa_l(iaa_k-1)+aa_u(iaa_k-1))/2
							!search given ia from iaa0 to iaaA
							ia = aa_u(iaa_k)
							iaa0 = aa_m( aa_l(iaa_k-1) )
							iaaA = aa_m( aa_u(iaa_k-1) )
							call maxVN(il,itr,idi,ial,id,ie,ia,iz,it, VN0,VD0,V0,wagehere,iaa0,iaaA,apol,ga,gadif,Vtest1)
							V_m(ia) = Vtest1
							aa_m(ia) = apol !agrid(apol)
							gapp((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = ga
							gapp_dif((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = gadif
							iaN = iaN+1
							ia_o(iaN) = ia
					

						enddo
						do
							if(iaa_k==1) exit outerVN
							if( aa_u(iaa_k)/= aa_u(iaa_k - 1) ) exit
							iaa_k = iaa_k -1
						end do
						aa_l(iaa_k) = aa_u(iaa_k)
						aa_u(iaa_k) = aa_u(iaa_k-1)
					end do outerVN

					aN((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,:,iz,it) = aa_m
					VN((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,:,iz,it) = V_m
					
					Vtest1 = sum((VN((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,:,iz,it) &
						& - VN0((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,:,iz,it))**2)
					summer = Vtest1 + summer
					if(print_lev >3) then
						call veci2csv(ia_o,"ia_o_VN.csv", wo)
						if(wo == 0) wo = 1
					endif
				enddo !ipara
			!$OMP END PARALLEL do
			
				!------------------------------------------------!			
				! Done making VN
					
				if (print_lev >3) then
					wo = 0
					itr = tri0
					do ial=1,nal	!Loop over alpha (ai)
					do ie=1,ne	!Loop over earnings index
					do iz=1,nz	!Loop over TFP
						! matrix in disability index and assets
						call mat2csv(VN((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"VN_it.csv",wo)
						call mati2csv(aN((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"aN_it.csv",wo)
						call mat2csv(VN((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"VU_it.csv",wo)
						call mati2csv(aN((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"aU_it.csv",wo)
						call mati2csv(gapp((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"gapp_it.csv",wo)
						call mat2csv(gapp_dif((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"gapp_dif_it.csv",wo)

						if(wo == 0 ) wo =1		  		
					enddo !iz 
					enddo !id 
					enddo !ial 
				endif
			
				!update VN0
				do ial=1,nal	!Loop over alpha (ai)
				do itr=1,ntr	!loop over trend
				do id=1,nd	!Loop over disability index
				do ie=1,ne	!Loop over earnings index
				do iz=1,nz	!Loop over TFP
					do ia =1,na
						VN0((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = VN((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it)
					enddo	!ia
				enddo !ial
				enddo !itr
				enddo !id
				enddo !ie
				enddo !iz

				!------------------------------------------------!
				!Solve VW given guesses on VW, VN, and implied V
				!------------------------------------------------!
				summer = 0.
				wo = 0
				npara = nal*ntr*nd*ne*nz
			!$OMP   parallel do reduction(+:summer) &
			!$OMP & private(ipara,ial,id,ie,iz,itr,apol,eprime,wagehere,iee1,iee2,iee1wt,ia,iaa0,iaaA,aa_l,aa_u,iaa_k,ia_o,iaN,Vtest1,VWhere,gwdif,gw) 
				do ipara = 1,npara
					iz = mod(ipara-1,nz)+1
					ie = mod(ipara-1,nz*ne)/nz + 1
					id = mod(ipara-1,nz*ne*nd)/(nz*ne) +1
					itr= mod(ipara-1,nz*ne*nd*ntr)/(nz*ne*nd) +1
					ial= mod(ipara-1,nz*ne*nd*ntr*nal)/(nz*ne*nd*ntr)+1

					!Earnings evolution independent of choices.
					wagehere = wage(trgrid(itr),alfgrid(ial),id,zgrid(iz,1),it) !<- zgrid should be index by ij
					eprime = Hearn(it,ie,wagehere)
					!linear interpolate for the portion that blocks off bounds on assets
					if((eprime > emin) .and. (eprime < emax)) then  ! this should be the same as if(eprime > minval(egrid) .and. eprime < maxval(egrid))
						iee1 = ne
						do while( (eprime < egrid(iee1)) .and. (iee1>= 1))
							iee1 = iee1 -1
						enddo
						iee2 = min(ne,iee1+1)
						iee1wt = (egrid(iee2)-eprime)/(egrid(iee2)-egrid(iee1))
					elseif( eprime <= emin  ) then 
						iee1wt = 1._dp
						iee1 = 1
						iee2 = 1
					else 
						iee1wt = 0.
						iee1 = ne
						iee2 = ne
					endif

					!----------------------------------------------------------------
					!Loop over current state: assets
					!----------------------------------------------------------------
					iaN = 0
					ia = 1
					iaa0 = 1
					iaaA = na
					call maxVW(il,itr,idi,ial,id,ie,ia,iz,it, VU, V0,wagehere,iee1,iee2,iee1wt, &
						& iaa0,iaaA,apol,gw,gwdif,Vtest1 ,VWhere )
					V	((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = Vtest1
					VW	((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = VWhere
					gwork	((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = gw
					gwork_dif((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = gwdif
					aW	((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = apol
					iaN = iaN+1
					ia_o(iaN) = ia
					

					ia = na
					iaa0 = aW((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,1,iz,it)
					iaaA = na
					call maxVW(il,itr,idi,ial,id,ie,ia,iz,it, VU, V0,wagehere,iee1,iee2,iee1wt, &
						& iaa0,iaaA,apol,gw,gwdif,Vtest1 ,VWhere )
					V	((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = Vtest1
					VW	((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = VWhere
					gwork	((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = gw
					gwork_dif((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = gwdif
					aW	((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = apol
					iaN = iaN+1
					ia_o(iaN) = ia
					
					iaa_k = 1
					aa_l(iaa_k) = 1
					aa_u(iaa_k) = na

					outerVW: do
						do
							if(aa_u(iaa_k) == aa_l(iaa_k)+1) exit
							iaa_k = iaa_k+1
							aa_l(iaa_k) = aa_l(iaa_k-1)
							aa_u(iaa_k) = (aa_l(iaa_k-1)+aa_u(iaa_k-1))/2
							!search given ia from iaa0 to iaaA
							ia = aa_u(iaa_k)
							iaa0 = aW((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,  aa_l(iaa_k-1)  ,iz,it)
							iaaA = aW((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,  aa_u(iaa_k-1)  ,iz,it)
							call maxVW(il,itr,idi,ial,id,ie,ia,iz,it, VU, V0,wagehere,iee1,iee2,iee1wt, &
								& iaa0,iaaA,apol,gw,gwdif,Vtest1 ,VWhere )
							V	((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = Vtest1
							VW	((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = VWhere
							gwork	((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = gw
							gwork_dif((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it)= gwdif
							aW	((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = apol
							iaN = iaN+1
							ia_o(iaN) = ia
						enddo
						do
							if(iaa_k==1) exit outerVW
							if( aa_u(iaa_k)/= aa_u(iaa_k - 1) ) exit
							iaa_k = iaa_k -1
						end do
						aa_l(iaa_k) = aa_u(iaa_k)
						aa_u(iaa_k) = aa_u(iaa_k-1)
					end do outerVW
					
					Vtest1 = sum((V((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,:,iz,it) &
						& - V0((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,:,iz,it))**2)

					summer = Vtest1	+ summer

					do ia=1,na
						maxer(ia,iz,ie,id,ial) = (V((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it)-V0((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it))**2
					enddo
					if(print_lev >3) then
						call veci2csv(ia_o,"ia_o_VW.csv", wo)
						if(wo == 0) wo = 1
					endif
	!				enddo !iz  enddo !ie   	enddo !id  	enddo !ial
				enddo
			!$OMP  END PARALLEL do
			
				maxer_v = maxval(maxer)
				maxer_i = maxloc(maxer)

				!update VW0, V0
				do ial=1,nal	!Loop over alpha (ai)
				do itr=1,ntr	!loop over trend
				do id=1,nd	!Loop over disability index
				do ie=1,ne	!Loop over earnings index
				do iz=1,nz	!Loop over TFP
				do ia =1,na
					VW0((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) = VW((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it)
					V0 ((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it) =  V((il-1)*ntr+itr,(idi-1)*nal+ial,id,ie,ia,iz,it)
				enddo !ia		  	
				enddo !ial
				enddo !itr
				enddo !id
				enddo !ie
				enddo !iz

								
				if (print_lev >2) then
					wo = 0
					itr = tri0
					do ial=1,nal	!Loop over alpha (ai)
					do ie=1,ne	!Loop over earnings index
					do iz=1,nz	!Loop over TFP
						! matrix in disability and assets
						call mat2csv(VW((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"VW_it.csv",wo)
						call mati2csv(aW((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"aW_it.csv",wo)
						call mati2csv(gwork((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"gwork_it.csv",wo)
						call mat2csv(gwork_dif((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"gwork_idf_it.csv",wo)
						if(wo==0) wo =1
					enddo !iz 
					enddo !ie 
					enddo !ial 	
				endif




	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
				! End of iter iteration
				!------------------------------------------------!
				!Check |V-V0|<eps
				!------------------------------------------------!
				if(verbose > 3 .and. mod(iter,100).eq. 0) then
					write(*,*) summer, iter, it, il
					write(*,*) maxer_v, maxer_i(1)
				endif
				if (summer < Vtol ) then
					if(verbose >= 2) then
						write(*,*) summer, iter, it, il
						write(*,*) maxer_v, maxer_i(1)
					endif
					exit !Converged				
				endif

				iter=iter+1
				if(iter>=maxiter-1) iter_timeout = iter_timeout+1
				smthV0param = smthV0param*1.5_dp !tighten up the discrete choice
			enddo	!iter: V-iter loop
	!WRITE(*,*) il, itr, idi, it
		enddo	!t loop, going backwards

		enddo	!idi

		enddo	!il

		if(verbose>1 .and. iter_timeout>0) print*, "did not converge ", iter_timeout, " times"
		! this plots work-rest and di application on the cross product of alphai and deltai and di
		if(print_lev >1) then
			itr = tri0
			il  = 1
			wo  = 0

			do id  = 1,nd
			do ie  = 1,ne
				call mati2csv(aD(id,ie,:,:),"aD"//trim(caselabel)//".csv",wo)
				call mat2csv (VD(id,ie,:,:),"VD"//trim(caselabel)//".csv",wo)

				call veci2csv(aR(id,ie,:),"aR"//trim(caselabel)//".csv",wo)
				call vec2csv (VR(id,ie,:),"VR"//trim(caselabel)//".csv",wo)
				if(wo == 0) wo =1
			enddo
			enddo

			wo = 0
			itr=tri0
			do idi=1,ndi	!loop over delta(idi)
			do ial=1,nal	!Loop over alpha (al)
			do ie=1,ne	!Loop over earnings index
			do iz=1,nz	!Loop over TFP
				do it = TT-1,1,-1
					! matrix in disability and assets
					call mat2csv(V((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"V"//trim(caselabel)//".csv",wo)

					call mat2csv(VW((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"VW"//trim(caselabel)//".csv",wo)
					call mati2csv(aW((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"aW"//trim(caselabel)//".csv",wo)

					call mat2csv(VU((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"VU"//trim(caselabel)//".csv",wo)
					call mati2csv(aU((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"aU"//trim(caselabel)//".csv",wo)

					call mat2csv(VN((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"VN"//trim(caselabel)//".csv",wo)
					call mati2csv(aN((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"aN"//trim(caselabel)//".csv",wo)

					call mati2csv(gwork((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"gwork"//trim(caselabel)//".csv",wo)
					call mat2csv(gwork_dif((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"gwork_dif"//trim(caselabel)//".csv",wo)

					call mati2csv(gapp((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"gapp"//trim(caselabel)//".csv",wo)
					call mat2csv(gapp_dif((il-1)*ntr+itr,(idi-1)*nal+ial,:,ie,:,iz,it) ,"gapp_dif"//trim(caselabel)//".csv",wo)

					if(wo==0) wo =1
				enddo !it
			enddo !iz 
			enddo !ie 
			enddo !ial 	
			enddo !idi
		endif

		deallocate(maxer)
		deallocate(VR0,VD0,VN0,VU0,VW0,V0)
	!		deallocate(VR,VD,VN,VU,VW,V)
	!		deallocate(aR,aD,aN,aW,aU,gwork,gapp,gapp_dif,gwork_dif)

	end subroutine sol 
end module sol_val


!**************************************************************************************************************!
!**************************************************************************************************************!
!						Simulate from solution					       !
!**************************************************************************************************************!
!**************************************************************************************************************!
module sim_hists
	use V0para
	use helper_funs
! module with subroutines to solve the model and simulate data from it 

	implicit none
	
	contains


	subroutine draw_fndsepi(fndsep_i_draw, fndsep_i_int, fndarrive_draw, j_i, seed0, success)
	! draws depreciation rates and indices on the delta grid (i.e at the discrete values)
		implicit none

		integer, intent(in) :: seed0
		integer, intent(in), dimension(:) :: j_i
		integer, intent(out) :: success
		real(dp), dimension(:,:) :: fndsep_i_draw,fndarrive_draw
		integer, dimension(:,:,:) :: fndsep_i_int
		integer :: ss=1, Nsim, m,i,it
		real(dp) :: fndgrid_i
		integer, allocatable :: bdayseed(:)

		call random_seed(size = ss)
		allocate(bdayseed(ss))
		forall(m=1:ss) bdayseed(m) = (m-1)*100 + seed0
		call random_seed(put = bdayseed(1:ss) )
		
		Nsim = size(fndsep_i_draw,1)

		do i=1,Nsim
			call random_number(fndgrid_i) ! draw uniform on 0,1
			fndsep_i_draw(i,1) = fndgrid_i
			call random_number(fndgrid_i) ! draw uniform on 0,1
			fndsep_i_draw(i,2) = fndgrid_i
			do it=1,Tsim
				call random_number(fndgrid_i) ! draw uniform on 0,1
				fndarrive_draw(i,it) = fndgrid_i
			enddo
		enddo

		call set_fndsepi(fndsep_i_int,fndsep_i_draw,j_i)
		success = 0
		deallocate(bdayseed)
	end subroutine draw_fndsepi
	
	subroutine set_fndsepi( fndsep_i_int,fndsep_i_draw,j_i)

		real(dp), dimension(:,:), intent(in) :: fndsep_i_draw
		integer , dimension(:,:,:), intent(out) :: fndsep_i_int
		integer, intent(in), dimension(:) :: j_i
		integer :: ss=1, si_int,fi_int,m,i,ij,iz
		real(dp) :: fndgridL, fndgridH,fndwtH,fndwtL,fndgrid_i
		real(dp) :: sepgridL, sepgridH,sepwtH,sepwtL,sepgrid_i
		real(dp), dimension(nl+1,nj,nz) :: fndcumwt,sepcumwt

		fndwt	 = 1._dp/dble(nl) ! initialize with equal weight
		sepwt	 = 1._dp/dble(nl) ! initialize with equal weight
		fndcumwt = 0.
		sepcumwt = 0.

		do iz=1,nz
			fndgridL = 0.
			sepgridL = 0.
			do i=1,nl/2
				fndgridL = fndgrid(i,iz)/dble(nl/2) + fndgridL
				sepgridL = sepgrid(i,iz)/dble(nl/2) + sepgridL
			enddo
			fndgridH = 0.
			sepgridH = 0.
			do i= 1+nl/2,nl
				fndgridH = fndgrid(i,iz)/dble(nl-nl/2) + fndgridH
				sepgridH = sepgrid(i,iz)/dble(nl-nl/2) + sepgridH
			enddo
			
			do ij=1,nj
				! choose the mean to match the target mean by occupation
				fndwtH = (fndrate(iz,ij)-fndgridL)/(fndgridH-fndgridL)
				sepwtH = (seprisk(iz,ij)-sepgridL)/(sepgridH-sepgridL)
				fndwtL = 1._dp - fndwtH
				sepwtL = 1._dp - sepwtH
				do i=1,nl/2
					fndwt(i,ij,iz) = fndwtL/dble(nl/2)
					sepwt(i,ij,iz) = sepwtL/dble(nl/2)
				enddo
				do i=1+nl/2,nl
					fndwt(i,ij,iz) = fndwtH/dble(nl-nl/2)
					sepwt(i,ij,iz) = sepwtH/dble(nl-nl/2)
				enddo
			enddo
			!setup fndcumwt,sepcumwt
			do ij=1,nj
				do i=1,nl
					fndcumwt(i+1,ij,iz) = fndwt(i,ij,iz) + fndcumwt(i,ij,iz)
					sepcumwt(i+1,ij,iz) = sepwt(i,ij,iz) + sepcumwt(i,ij,iz)
				enddo
			enddo
		enddo !iz

		do iz=1,nz
		do i=1,Nsim
			fndgrid_i = fndsep_i_draw(i,1)
			sepgrid_i = fndsep_i_draw(i,2)
			fi_int = finder(fndcumwt(:,j_i(i),iz),fndgrid_i)
			si_int = finder(sepcumwt(:,j_i(i),iz),sepgrid_i)
			fndsep_i_int(i,1,iz) = fi_int			
			fndsep_i_int(i,2,iz) = si_int
		enddo
		enddo
	
		if(print_lev >=2) &
		&	call mat2csv(fndwt(:,:,2),"fndwt"//trim(caselabel)//".csv")
		if(print_lev >=2) &
		&	call mat2csv(sepwt(:,:,2),"sepwt"//trim(caselabel)//".csv")
	
	end subroutine set_fndsepi


	subroutine draw_deli(del_i_draw, del_i_int, j_i, seed0, success)
	! draws depreciation rates and indices on the delta grid (i.e at the discrete values)
		implicit none

		integer, intent(in) :: seed0
		integer, intent(in), dimension(:) :: j_i
		integer, intent(out) :: success
		real(dp), dimension(:) :: del_i_draw
		integer, dimension(:) :: del_i_int
		integer :: ss=1, Ndraw, m,i
		real(dp) :: delgrid_i
		integer, allocatable :: bdayseed(:)

		call random_seed(size = ss)
		allocate(bdayseed(ss))
		forall(m=1:ss) bdayseed(m) = (m-1)*100 + seed0
		call random_seed(put = bdayseed(1:ss) )
		
		Ndraw = size(del_i_draw)

		do i=1,Ndraw
			call random_number(delgrid_i) ! draw uniform on 0,1
			del_i_draw(i) = delgrid_i
		enddo

		call set_deli(del_i_int,del_i_draw,j_i)
		
		success = 0
		deallocate(bdayseed)
	end subroutine draw_deli
	
	subroutine set_deli( del_i_int,del_i_draw,j_i)

		real(dp), dimension(:), intent(in) :: del_i_draw
		integer , dimension(:), intent(out) :: del_i_int
		integer, intent(in), dimension(:) :: j_i
		integer :: ss=1, di_int,m,i,ij,idi
		real(dp) :: delgridL, delgridH,delwtH,delwtL,delgrid_i


		delwt	 = 1._dp/dble(ndi) ! initialize with equal weight
		if(del_by_occ .eqv. .true.) then ! give weight according to mean delta by occ
			delgridL = 0. !average of high cells
			do i=1,ndi/2
				delgridL = delgrid(i)/dble(ndi/2) + delgridL
			enddo
			delgridH = 0. !average of low cells
			do i= 1+ndi/2,ndi
				delgridH = delgrid(i)/dble(ndi-ndi/2) + delgridH
			enddo
			do ij=1,nj
				! choose the mean to match the target mean by occupation
				delwtH = (occdel(ij)-delgridL)/(delgridH-delgridL)
				delwtL = 1._dp - delwtH
				do i=1,ndi/2
					delwt(i,ij) = delwtL/dble(ndi/2)
				enddo
				do i=1+ndi/2,ndi
					delwt(i,ij) = delwtH/dble(ndi-ndi/2)
				enddo
			enddo
		else
			delgridL = delgrid(1)
			delgridH = delgrid(ndi)
			do ij=1,nj
				delwt(:,ij) = 0.
				if(delgridH - delgridL > 1e-4) then
					delwtH = (1. - delgridL)/(delgridH-delgridL)
					delwtL = 1._dp - delwtH
					do i=1,ndi/2
						delwt(i,:) = delwtL/dble(ndi/2)
					enddo
					do i=1+ndi/2,ndi
						delwt(i,:) = delwtH/dble(ndi-ndi/2)
					enddo
				else
					delwt(1,:)=1.
				endif
			enddo
		endif
		!setup delcumwt
		delcumwt = 0.
		do ij=1,nj
			do idi=1,ndi
				delcumwt(idi+1,ij) = delwt(idi,ij) + delcumwt(idi,ij)
			enddo
		enddo

		delgridL = minval(delgrid)
		delgridH = maxval(delgrid)
		do i=1,Nsim
			delgrid_i = del_i_draw(i)
			di_int = finder(delcumwt(:,j_i(i)),delgrid_i)
			di_int = max(1, min(di_int,ndi))
			del_i_int(i) = di_int			
		enddo
	
		if(print_lev >=2) &
		&	call mat2csv(delwt,"delwt"//trim(caselabel)//".csv")
	
	end subroutine set_deli
	
	subroutine draw_status_innov(status_it_innov, health_it_innov, seed0, success)
	! draws innovations to d, will be used if working and relevant
		implicit none

		integer, intent(in) :: seed0
		integer, intent(out) :: success
		real(dp), dimension(:,:) :: status_it_innov, health_it_innov
		integer :: ss=1, m,i,it
		real(dp) :: s_innov
		integer, allocatable :: bdayseed(:)

		call random_seed(size = ss)
		allocate(bdayseed(ss))
		forall(m=1:ss) bdayseed(m) = (m-1)*100 + seed0
		call random_seed(put = bdayseed(1:ss) )

		do i=1,Nsim
			do it=1,Tsim
				call rand_num_closed(s_innov)
				status_it_innov(i,it) = s_innov
				call random_number(s_innov)
				health_it_innov(i,it) = s_innov
			enddo
		enddo
		success = 0
		deallocate(bdayseed)
	end subroutine draw_status_innov

	subroutine draw_alit(al_it,al_it_int, seed0, success)
	! draws alpha shocks and idices on the alpha grid (i.e at the discrete values)
		implicit none

		integer, intent(in) :: seed0
		integer, intent(out),optional :: success
		real(dp), dimension(:,:) :: al_it
		integer, dimension(:,:) :: al_it_int
		integer :: ss=1, Ndraw, alfgrid_int, t,m,i,k
		real(dp) :: alfgridL, alfgridH,alf_innov,alfgrid_i,alf_i
		real(dp) :: alfgrid_minE,alfgrid_maxE,alfgrid_Uval !min max value while employed and val of unemp
		integer, allocatable :: bdayseed(:)
		real(dp), allocatable :: cumpi_al(:,:)

		allocate(cumpi_al(nal,nal+1))

		alfgrid_minE = alfgrid(2)
		alfgrid_maxE = alfgrid(nal)
		alfgrid_Uval = alfgrid(1)

		call random_seed(size = ss)
		allocate(bdayseed(ss))
		forall(m=1:ss) bdayseed(m) = (m-1)*100 + seed0
		call random_seed(put = bdayseed(1:ss) )

		cumpi_al =0.
		Ndraw = size(al_it,1)

		do i=1,nal
			do k=2,nal+1
				cumpi_al(i,k) = pialf(i,k-1)+cumpi_al(i,k-1)
			enddo
		enddo

		success =0
		!
		do i=1,Ndraw

			! draw starting values
			t =1
			
			call random_normal(alf_innov) ! draw normal disturbances on 0,1
			! transform it by the ergodic distribution for the first period:
			alf_i = alf_innov*alfsig + alfmu

			if(alf_i >alfgrid_maxE .or. alf_i < alfgrid_minE) success = 1+success !count how often we truncate
			!impose bounds
			alf_i = max(alf_i,alfgrid_minE)
			alf_i = min(alf_i,alfgrid_maxE)
			alfgrid_int = finder(alfgrid,alf_i)
			alfgrid_int = max(2, min(alfgrid_int,nal) )
			! round up or down:
			
			if(al_contin .eqv. .true.) then
				al_it(i,t) = alf_i ! log of wage shock
			else
				if( (alf_i - alfgrid(alfgrid_int))/(alfgrid(alfgrid_int+1)- alfgrid(alfgrid_int)) >0.5 ) alfgrid_int = alfgrid_int + 1
				al_it(i,t) = alfgrid(alfgrid_int) ! log of wage shock, on grid
				alfgrid_i = alf_i
			endif
			al_it_int(i,t) = alfgrid_int
			
			
			! draw sequence:
			do t=2,Tsim
				if(al_contin .eqv. .true.) then
					!call rand_num_closed(alf_innov)
					! unemployment risk
					!if( alf_innov < cumpi_al(alfgrid_int,2)) then
					!	alf_i = alfgrid(1)
					!	al_it(i,t) = alf_i
					!	alfgrid_int = 1
					!else
						call random_normal(alf_innov)
						alf_i  = alfrho*alf_i + (1.-alfrho**2)*alfsig*alf_innov + alfmu
						al_it(i,t) = alf_i  ! log of wage shock
						alfgrid_int = finder(alfgrid,alf_i)
						alfgrid_int = max(min(alfgrid_int,nal),2)
					!endif
				else
					call rand_num_closed(alf_innov)
					alfgrid_int = finder(cumpi_al(alfgrid_int,:), alf_innov )
					alfgrid_int = max(min(alfgrid_int,nal),1)
					al_it(i,t) = alfgrid(alfgrid_int) ! log of wage shock, on grid
				endif
				al_it_int(i,t) = alfgrid_int					
			enddo
		enddo
		if(success > 0.2*Ndraw*Tsim)  success = success
		if(success <= 0.2*Ndraw*Tsim) success = 0
		!call mat2csv(cumpi_al,"cumpi_al.csv")
		deallocate(cumpi_al)
		deallocate(bdayseed)
	end subroutine draw_alit

	subroutine draw_ji(j_i,jshock_ij,born_it,seed0, success)
		implicit none
		integer	:: j_i(:),born_it(:,:)
		real(dp) :: jshock_ij(:,:)
		real(dp) :: jwt
		integer	:: i,m,ss=1,ij,it
		integer,intent(in)  :: seed0
		integer,intent(out) :: success
		integer, allocatable :: bdayseed(:)
		real(dp) :: Njcumdist(nj+1,Tsim)
		real(dp) :: draw_i
		
		Njcumdist = 0
		j_i = 0
		if(nj>1) then
			call random_seed(size = ss)
			allocate(bdayseed(ss))
			forall(m=1:ss) bdayseed(m) = (m-1)*100 + seed0
			call random_seed(put = bdayseed(1:ss) )
			if(j_rand .eqv. .false. ) then
				!draw gumbel-distributed shock
				do i = 1,Nsim
					do ij = 1,nj
						call random_gumbel(draw_i)
						jshock_ij(i,ij) = draw_i
					enddo
				enddo
			else
			jshock_ij = 0._dp
			!do periods 2:Tsim
				do it=2,Tsim
					do ij=1,nj
						Njcumdist(ij+1,it) = occpr_trend(it,ij) + Njcumdist(ij,it)
					enddo
					do i=1,Nsim
						if( born_it(i,it)==1) then
							call random_number(draw_i)
							j_i(i) = finder(Njcumdist(:,it),draw_i)
							if(j_i(i) < 1 ) j_i(i) = 1
							if(j_i(i) > nj) j_i(i) = nj
						endif
					enddo
				enddo
			!do period 1
				it=1
				do ij=1,nj
					Njcumdist(ij+1,it) = occsz0(ij) + Njcumdist(ij,it)
				enddo

				do i=1,Nsim
					if( j_i(i) ==0) then !not born in 2:Tsim and so doesn't have an occupation yet
						call random_number(draw_i)
						j_i(i) = finder(Njcumdist(:,it),draw_i)
						if(j_i(i) < 1 ) j_i(i) = 1
						if(j_i(i) > nj) j_i(i) = nj
					endif
				enddo
			endif
			!make sure everyone has a job:
			do i=1,Nsim
				if( j_i(i)==0 ) then 
					call random_number(draw_i)
					j_i(i) = nint( draw_i*(nj-1)+1 )
				endif
			enddo
			
			
			deallocate(bdayseed)
		else
			jshock_ij = 0.
			j_i = 1
		endif
		success = 0

	end subroutine draw_ji

	subroutine draw_zjt(z_jt_select, z_jt_innov, seed0, success)
		implicit none

		real(dp), intent(out) :: z_jt_innov(:) !this will drive the continuous AR process
		real(dp), intent(out) :: z_jt_select(:) !this will select the state if we use a markov chain
		integer	:: it=1,i=1,ij=1,iz=1,izp=1,m=1,ss=1
		integer,intent(in) :: seed0
		integer,intent(out) :: success
		integer, allocatable :: bdayseed(:) 
		integer :: NBER_start_stop(5,2)
		real(dp) :: z_innov=1.
		integer  :: nzblock = nz/2
		
		if(z_regimes .eqv. .true.) then
			nzblock = nz/2
		else
			nzblock = nz
		endif
		
		call random_seed(size = ss)
		allocate(bdayseed(ss))
		forall(m=1:ss) bdayseed(m) = (m-1)*100 + seed0
		call random_seed(put = bdayseed(1:ss) )

		NBER_start_stop = 0
		!compute NBER dates in case of NBER_tseq == 1 
		!NO LONGER: 1980 + 0/4 -> 1980 + 2/4
		!NO LONGER: 1981 + 2/4 -> 1982 + 3/4
		
		! 1990 + 2/4 -> 1991 + 0/4
		! 2001 + 2/4 -> 2001 + 3/4
		! 2007 + 3/4 -> 2009 + 1/4
		NBER_start_stop(1,1) =  7*itlen + 2*( itlen/4 ) +1
		NBER_start_stop(1,2) =  8*itlen + 0*( itlen/4 ) +1
		NBER_start_stop(2,1) = 18*itlen + 2*( itlen/4 ) +1
		NBER_start_stop(2,2) = 18*itlen + 3*( itlen/4 ) +1
		NBER_start_stop(3,1) = 24*itlen + 3*( itlen/4 ) +1
		NBER_start_stop(3,2) = 26*itlen + 1*( itlen/4 ) +1
		!start cycles on 1st

		ss = 1
		do it = 1,Tsim
			if(NBER_tseq .eqv. .true. ) then
				if((it >= NBER_start_stop(ss,1)) .and. (it <= NBER_start_stop(ss,2)) ) then
					z_jt_innov(it) = -1.
					z_jt_select(it) = 0.
				else
					z_jt_innov(it)  = 1.
					z_jt_select(it) = 1.
				endif
				if(it .eq. NBER_start_stop(ss,2) .and. ss < 5) &
					& ss = ss+1
			else
				call random_normal(z_innov)
				z_jt_innov(it) = z_innov
				z_jt_select(it) = alnorm(z_innov,.false.)
			endif	
		enddo
		success = 0
		deallocate(bdayseed)
		!call mat2csv(cumpi_z,"cumpi_z.csv")
	end subroutine draw_zjt
	
	subroutine draw_age_it(age_it, born_it, age_draw,seed0, success)

		integer,intent(out) :: age_it(:,:),born_it(:,:)
		real(dp), intent(out) :: age_draw(:,:)
		integer	:: i,m, Nm,ss=1
		integer,intent(in) :: seed0
		integer,intent(out) :: success
		integer, allocatable :: bdayseed(:)
		real(dp) :: rand_age,rand_born
		
		call random_seed(size = ss)
		allocate(bdayseed(ss))
		forall(m=1:ss) bdayseed(m) = (m-1)*100 + seed0
		call random_seed(put = bdayseed(1:ss) )

		Nm = size(age_draw,2)
		
		do i =1,Nsim
			do m = 1,Nm
				call random_number(rand_born)
				age_draw(i,m) = rand_born
			enddo! m=1,50.... if never gets born
		enddo! i=1,Nsim

		call set_age(age_it,born_it,age_draw)

		deallocate(bdayseed)
		success = 0
	end subroutine draw_age_it
	
	subroutine set_age(age_it, born_it, age_draw)
		
		integer,intent(out) :: age_it(:,:),born_it(:,:)
		real(dp), intent(in) :: age_draw(:,:)
		integer	:: it,itp,i,m,m1,m2,m3,Nm,bn_i, age_ct, age_jump
		real(dp), dimension(TT) :: cumpi_t0
		real(dp), dimension(TT-1) :: prob_age_nTT
		real(dp) :: rand_age,rand_born
		real(dp), dimension(Tsim) :: hazborn_hr_t,prborn_hr_t,cumprnborn_t
		
		
		!set up cumulative probabilities for t0 and conditional draws
		!not begining with anyone from TT
		if(demog_dat .eqv. .true.) then
			prob_age_nTT = prob_age(:,1)
			!also include TT
			!prob_age_nTT = prob_age
			prborn_hr_t  = prborn_t
			hazborn_hr_t = hazborn_t
			cumprnborn_t(1) = prborn_t(1)
			do it=2,Tsim
				cumprnborn_t(it) = prborn_hr_t(it) + cumprnborn_t(it-1)
			enddo
			cumprnborn_t = cumprnborn_t/cumprnborn_t(Tsim)
		else !solve for a flat age profile
			prborn_hr_t = prborn_constpop
			hazborn_hr_t = hazborn_constpop
			do it=2,Tsim
				hazborn_hr_t(it) = prborn_hr_t(it)/cumprnborn_t(it-1)
				cumprnborn_t(it) = (1.-prborn_hr_t(it))*cumprnborn_t(it-1)
			enddo
		endif
		
		cumpi_t0 = 0.
		age_it = 0.
		do it=1,TT-1
			cumpi_t0(it+1) = prob_age_nTT(it) + cumpi_t0(it)
		enddo

		Nm = size(age_draw,2)
		born_it = 0
		do i =1,Nsim
!~ 		do m =1,maxiter
			!pick the birthdate
			!it = finder(cumprnborn_t, dble(i-1)/dble(Nsim-1))
			it = finder(cumprnborn_t, age_draw(i,1))
			if(it>1) then
				age_it(i,it) =1
				born_it(i,it) = 1
				age_ct = 0
				bn_i = 0 ! initialize, not yet born
			else
				rand_age = age_draw(i,2 )
				age_it(i,it) = finder(cumpi_t0,rand_age)
				born_it(i,it) = 0
				if(age_it(i,it)==1) then
					age_ct = nint(age_draw(i,3)*youngD*tlen)
				else
					age_ct = nint(age_draw(i,3)*oldD*tlen)
				endif
				bn_i = 1 ! initialize, born
			endif
			!count up periods:
			do it=2,Tsim
				if(age_it(i,it-1)<TT) then
					if(born_it(i,it)== 1 .and. ( bn_i == 0) ) then
						age_it(i,it) =1
						born_it(i,it) = 1
						bn_i = 1
						age_ct = 0
					elseif(bn_i == 1) then
						born_it(i,it) = 0
						age_ct = age_ct+1
						!if(age_it(i,it-1)==1) age_jump = nint(youngD)*itlen - 1
						!if(age_it(i,it-1) >1) age_jump = nint(oldD)*itlen - 1 
						!if((age_ct >= age_jump ) .and. (age_it(i,it-1) < TT) ) then
						if((age_draw(i,it+3) <1.- ptau( age_it(i,it-1) ) ) .and. (age_it(i,it-1) < TT) ) then
							age_it(i,it) = age_it(i,it-1)+1
							age_ct = 0
						else 
							age_it(i,it) = age_it(i,it-1)
						endif
					else 
						bn_i = 0
						born_it(i,it) = 0
						age_it(i,it) = 0
					endif
				else
					age_it(i,it) = TT
					born_it(i,it) = 0
				endif
			enddo		
!~ 		if(sum(age_it(i,:))>0) then
!~ 			exit
!~ 		else !re-shuffle birthdates
		
!~ 		endif
		
		enddo! i=1,Nsim
	
	end subroutine set_age

	subroutine draw_draw(drawi_ititer, drawt_ititer, age_it, seed0, success)

		integer,intent(in) :: seed0
		integer,intent(out) :: success
		integer,intent(in) :: age_it(:,:)
		integer, allocatable :: bdayseed(:)
		integer,intent(out) :: drawi_ititer(:,:),drawt_ititer(:,:)
		integer :: i,it,id,m,ss=1,drawt,drawi,ndraw,Ncols, seedi,brn_yr(Nsim)
		real(dp) :: junk

		!only draws from init_yrs

		call random_seed(size = ss)
		allocate(bdayseed(ss))
		Ndraw = size(drawi_ititer,1)
		Ncols = size(drawi_ititer,2)
		do i =1,Nsim
			if(age_it(i,1)>0) then
				brn_yr(i) = 1
			else 
				do it=2,Tsim
					if(age_it(i,it)>0) then
						brn_yr(i) = it
						exit
					endif
				enddo
			endif
		enddo
		!need to draw these from age-specific distributions for iterations > 1
		! OMP parallel do firstprivate(id, i, it, junk, seedi, drawi, drawt,ss,bdayseed,m) <- this makes it much slower
		do id = 1,Ncols
			seedi = seed0+id
			do m=1,ss
				bdayseed(m) = (m-1)*100 + seedi
			enddo
			call random_seed(put = bdayseed )		
			do i=1,Ndraw
				it=brn_yr(i)
				ageloop: do 
					call random_number(junk)
					drawi = max(1,idnint(junk*Nsim))
					call random_number(junk)
					if( it==1 ) then
						drawt = max(1,init_yrs*idnint(junk*tlen)) !max(1,idnint(junk*(dble(Tblock_sim)*tlen)-1))
					else
						drawt = max(1,idnint(junk*Tsim))
					endif
					if(age_it(drawi,drawt) .eq. age_it(i,it)) then
						exit ageloop
					endif
				end do ageloop
				drawi_ititer(i,id) = drawi
				drawt_ititer(i,id) = drawt
			enddo
		enddo
		! OMP end parallel do
		
		deallocate(bdayseed)
		success = 0
	end subroutine


	subroutine draw_shocks(shk)

		implicit none
		type(shocks_struct) :: shk
		integer :: seed0,seed1, status
		integer :: time0,timeT,timert

		seed0 = 941987
		seed1 = 12281951
		call system_clock(count_rate = timert)
		
		call system_clock(count = time0)
		if(verbose >2) print *, "Drawing types and shocks"	
		call draw_age_it(shk%age_hist,shk%born_hist,shk%age_draw,seed0,status)
		seed0 = seed0 + 1
		call draw_ji(shk%j_i,shk%jshock_ij,shk%born_hist,seed1, status)
		seed1 = seed1 + 1
		call draw_alit(shk%al_hist,shk%al_int_hist, seed0, status)
		seed0 = seed0 + 1
		call draw_deli(shk%del_i_draw, shk%del_i_int, shk%j_i, seed1, status)
		seed1 = seed1 + 1
		call draw_fndsepi(shk%fndsep_i_draw, shk%fndsep_i_int, shk%fndarrive_draw, shk%j_i, seed0, status)
		seed0 = seed0 + 1
		call draw_zjt(shk%z_jt_select,shk%z_jt_innov, seed1, status)
		seed1 = seed1 + 1
		call draw_draw(shk%drawi_ititer, shk%drawt_ititer, shk%age_hist, seed0, status)
		seed0 = seed0 + 1
		call draw_status_innov(shk%status_it_innov, shk%health_it_innov,seed1, status)
		seed1 = seed1 + 1
		
		shk%drawn = 1
		call system_clock(count = timeT)
		print *, "draws took: ", dble((timeT-time0))/dble(timert)
		! check the distributions
		if(print_lev > 1 ) then
			call mat2csv(shk%jshock_ij,"jshock_ij_hist"//trim(caselabel)//".csv")
			call vec2csv(shk%del_i_draw,"del_i_draw_hist"//trim(caselabel)//".csv")
			call veci2csv(shk%j_i,"j_i_hist"//trim(caselabel)//".csv")
			call mat2csv(shk%al_hist,"al_it_hist"//trim(caselabel)//".csv")
			call vec2csv(shk%z_jt_innov,"z_jt_innov_hist"//trim(caselabel)//".csv")
			call mati2csv(shk%al_int_hist,"al_int_it_hist"//trim(caselabel)//".csv")
			call mati2csv(shk%age_hist,"age_it_hist"//trim(caselabel)//".csv")
			call mati2csv(shk%drawi_ititer,"drawi_hist"//trim(caselabel)//".csv")
		endif
		
	end subroutine draw_shocks

	subroutine set_zjt(z_jt_macroint, z_jt_panel, shk)
	
		type(shocks_struct), intent(in) :: shk
		real(8) :: z_jt_panel(:,:)
		integer :: z_jt_macroint(:)
		! for selecting the state of zj
		real(dp) :: cumpi_z(nz,nz+1)
		real(dp), allocatable :: cumpi_zblock(:,:)
		real(dp) ::  cumergpi(nz+1)
	
		integer :: it,ij,iz,izp, zi_jt_t , nzblock
		real(8) :: muhere, Zz_t

		if( z_regimes .eqv. .true.) then
			nzblock = nz/2
		else
			nzblock = nz
		endif
		allocate(cumpi_zblock(nzblock,nzblock+1))

		call settfp() ! sets values for piz


		cumpi_z = 0.
		cumpi_zblock = 0.
		cumergpi = 0.
		! for random transitions of time block or if z_regimes .eqv. .false.
		do iz=1,nz
			do izp=1,nz
				cumpi_z(iz,izp+1) = piz(iz,izp) + cumpi_z(iz,izp)
			enddo
		enddo
		! for deterministic transition of time block
		if(z_regimes .eqv. .true.) then
			do iz=1,nz/2
				do izp=1,nz/2
					cumpi_zblock(iz,izp+1) = piz(iz,izp) + cumpi_zblock(iz,izp)
				enddo
				cumpi_zblock(iz,:) = cumpi_zblock(iz,:)/cumpi_zblock(iz,nz/2)
				cumergpi(iz+1) = cumergpi(iz)+ ergpiz(iz)
			enddo
		else 
			cumpi_zblock = cumpi_z
		endif
		
		it = 1
		zi_jt_t = finder( cumergpi,shk%z_jt_select(it) )
		z_jt_macroint(it) = zi_jt_t
		Zz_t = zsig*shk%z_jt_innov(it)
		forall (ij = 1:nj)	z_jt_panel(ij,it) = Zz_t*zscale(ij)
		
		do it= 2,Tsim
			!z_jt_t = finder(cumpi_z(z_jt_t,:),z_innov ) <- random time-block transitions:

			! use conditional probability w/in time block
			zi_jt_t = finder(cumpi_zblock(zi_jt_t,:),shk%z_jt_select(it) )
			if( (it >= Tblock_sim*itlen) .and. (z_regimes .eqv. .true.)) then
				z_jt_macroint(it) = zi_jt_t  + nz/2
			else
				z_jt_macroint(it) = zi_jt_t
			endif
			
			
			Zz_t = (1.-zrho) * zmu + zsig*shk%z_jt_innov(it) + zrho*Zz_t
			do ij=1,nj
				if((it>= Tblock_sim*itlen) .and. (z_regimes .eqv. .true.)) then 
					muhere = zshift(ij)
				else
					muhere = 0.
				endif
				
				if( zj_contin .eqv. .true.) then
					!z_jt_panel(ij,it) = (1.-zrho)*muhere + zsig*shk%z_jt_innov(it) + zrho*z_jt_panel(ij,it-1)
					z_jt_panel(ij,it) = Zz_t*zscale(ij) + (1.-zrho)*muhere
				else
					z_jt_panel(ij,it) = zgrid(z_jt_macroint(it),ij)
				endif
			enddo
		enddo
	
		deallocate(cumpi_zblock)
	
	end subroutine set_zjt

	
	subroutine sim(vfs, pfs,hst,shk,occaggs)
		
		implicit none

		type(val_struct), intent(inout), target :: vfs
		type(pol_struct), intent(inout), target :: pfs	
		type(hist_struct), intent(inout), target :: hst
		type(shocks_struct), intent(inout), target :: shk
		
		logical, optional :: occaggs

		integer :: i=1, ii=1, iter=1, it=1, it_old=1, ij=1,il=1, idi=1, id=1, Tret=1,wo=1, &
			&  seed0=1, seed1=1, status=1, m=1,ss=1, iter_draws=5,Ncol=100,nomatch=0


		integer, allocatable :: work_it(:,:), app_it(:,:) !choose work or not, apply or not
		integer, allocatable :: a_it_int(:,:),e_it_int(:,:)
!		integer, allocatable :: hlthvocSSDI(:,:) ! got into ssdi on health or vocational considerations, 0= no ssdi, 1=health, 2=vocation
		real(dp), allocatable :: e_it(:,:), median_wage(:,:)
		
		! FOR DEBUGGING
		real(dp), allocatable :: val_hr_it(:)
		! because the actual alpha is endgoenous to unemployment and trend
		real(dp), allocatable :: al_it_endog(:,:)
		integer, allocatable  :: al_int_it_endog(:,:)
		real(dp), allocatable :: wtr_it(:,:)
		
		! write to hst, get from shk
		real(dp), pointer    :: work_dif_it(:,:), app_dif_it(:,:) !choose work or not, apply or not -- latent value
		real(dp), pointer	 :: di_prob_it(:,:)
		integer, pointer     :: born_it(:,:) ! born status, drawn randomly		
		real(dp), pointer	 ::	del_i_draw(:)
		integer, pointer     :: del_i_int(:)  ! integer valued shocks
		integer, pointer     :: fndsep_i_int(:,:,:)  ! integer valued shocks
		integer, pointer     :: status_it(:,:)	!track W,U,N,D,R : 1,2,3,4,5
		integer, pointer     :: age_it(:,:)	! ages, drawn randomly
		integer, pointer     :: j_i(:)		! occupation, maybe random
		integer, pointer     :: d_it(:,:) 	! disability status
		integer, pointer     :: z_jt_macroint(:)! shocks to be drawn
		real(8), pointer     :: z_jt_panel(:,:)! shocks to be drawn
		
		integer, pointer     :: al_it_int(:,:)! integer valued shocks
		real(dp), pointer    :: occgrow_jt(:,:), occshrink_jt(:,:), occsize_jt(:,:)
		real(dp), pointer    :: a_it(:,:) 	! assets
		real(dp), pointer    ::	al_it(:,:)	! individual shocks
		real(dp), pointer    :: status_it_innov(:,:),health_it_innov(:,:),fndarrive_draw(:,:)
		real(dp), pointer    :: jshock_ij(:,:)
		integer,  pointer    :: drawi_ititer(:,:)
		integer,  pointer    :: drawt_ititer(:,:)

		real(dp), pointer	 :: z_jt_innov(:)
		real(dp), pointer	 :: z_jt_select(:)


		! read from vals
		real(dp), pointer ::	V(:,:,:,:,:,:,:)	!Participant

		! read from pols
		real(dp), pointer ::	gapp_dif(:,:,:,:,:,:,:), gwork_dif(:,:,:,:,:,:,:) ! latent value of work/apply
	
		integer, pointer ::	aR(:,:,:), aD(:,:,:,:), aU(:,:,:,:,:,:,:), &
					aN(:,:,:,:,:,:,:), aW(:,:,:,:,:,:,:)
		integer, pointer ::	gapp(:,:,:,:,:,:,:), &
					gwork(:,:,:,:,:,:,:)

		logical :: ptrsuccess=.false., dead = .false.
		real(dp) :: cumpid(nd,nd+1,ndi,TT-1),pialf_conddist(nal), cumptau(TT+1),a_mean(TT-1),d_mean(TT-1),a_var(TT-1), &
				& d_var(TT-1),a_mean_liter(TT-1),d_mean_liter(TT-1),a_var_liter(TT-1),d_var_liter(TT-1), cumPrDage(nd+1,TT), &
				& s_mean(TT-1),s_mean_liter(TT-1), occgrow_hr(nj),occsize_hr(nj),occshrink_hr(nj),PrAl1(nz),PrAl1St3(nz),totpopz(nz),&
				& simiter_dist(maxiter)
	
		! Other
		real(dp)	:: wage_hr=1.,al_hr=1., junk=1.,a_hr=1., e_hr=1., z_hr=1., iiwt=1., ziwt=1., jwt=1., cumval=1., &
					&	work_dif_hr=1., app_dif_hr=1.,js_ij=1., Nworkt=1., ep_hr=1.,apc_hr = 1., sepi=1.,fndi = 1., hlthprob,al_last_invol,triwt=1.

		integer :: ali_hr=1,iiH=1,d_hr=1,age_hr=1,del_hr=1, zi_hr=1, ziH=1,il_hr=1 ,j_hr=1, ai_hr=1,api_hr=1,ei_hr=1,triH, &
			& tri=1, tri_hr=1,fnd_hr(nz),sep_hr(nz),status_hr=1,status_tmrw=1,drawi=1,drawt=1, invol_un = 0
			
		logical :: w_strchng_old = .false., final_iter = .false.,occaggs_hr =.true.
		
		if(present(occaggs)) then
			occaggs_hr = occaggs
		else
			occaggs_hr = .true.
		endif
		
		!************************************************************************************************!
		! Allocate things
		!************************************************************************************************!

		iter_draws = min(maxiter,100) !globally set variable
		
		allocate(a_it_int(Nsim,Tsim))		
		allocate(e_it(Nsim,Tsim))
		allocate(e_it_int(Nsim,Tsim))		
		allocate(work_it(Nsim,Tsim))
		allocate(app_it(Nsim,Tsim))
		allocate(al_int_it_endog(Nsim,Tsim))
		allocate(al_it_endog(Nsim,Tsim))
		allocate(wtr_it(Nsim,Tsim))
!		allocate(hlthvocSSDI(Nsim,Tsim))


		!!!!!!!!!!!!!!! DEBUGGING
		allocate(val_hr_it(Nsim))
		
		!************************************************************************************************!
		! Pointers
		!************************************************************************************************!
		! (disability extent, earn hist, assets)

		V => vfs%V !need this for the career choice
		aR => pfs%aR
		aD => pfs%aD
		aN => pfs%aN
		aW => pfs%aW
		aU => pfs%aU
		gwork => pfs%gwork
		gapp => pfs%gapp

		gapp_dif    => pfs%gapp_dif
		gwork_dif   => pfs%gwork_dif
		

		z_jt_innov  => shk%z_jt_innov
		z_jt_select => shk%z_jt_select
		del_i_int   => shk%del_i_int
		fndsep_i_int   => shk%fndsep_i_int
		del_i_draw  => shk%del_i_draw
		j_i         => shk%j_i
		al_it       => shk%al_hist
		al_it_int	=> shk%al_int_hist
		age_it 	    => shk%age_hist
		born_it	    => shk%born_hist
		status_it_innov => shk%status_it_innov
		health_it_innov => shk%health_it_innov
		fndarrive_draw  => shk%fndarrive_draw
		jshock_ij  	 	=> shk%jshock_ij  
		drawi_ititer    => shk%drawi_ititer
		drawt_ititer    => shk%drawt_ititer


		status_it   => hst%status_hist
		work_dif_it => hst%work_dif_hist
		app_dif_it  => hst%app_dif_hist
		di_prob_it 	=> hst%di_prob_hist
		d_it        => hst%d_hist
		z_jt_macroint  => hst%z_jt_macroint
		z_jt_panel  => hst%z_jt_panel
		a_it        => hst%a_hist		
		occgrow_jt  => hst%occgrow_jt
		occshrink_jt=> hst%occshrink_jt
		occsize_jt  => hst%occsize_jt
		
		ptrsuccess = associated(d_it,hst%d_hist)
		if(verbose>1) then
			if(ptrsuccess .eqv. .false. ) print *, "failed to associate d_it"
			ptrsuccess = associated(age_it,shk%age_hist)
			if(ptrsuccess .eqv. .false. ) print *, "failed to associate age_it"
			ptrsuccess = associated(V,vfs%V)
			if(ptrsuccess .eqv. .false. ) print *, "failed to associate V"
		endif

		hst%wage_hist    = 0.
		Tret = (Longev - youngD - oldD*oldN)*tlen
		work_dif_it      = 0.
		app_dif_it       = 0.
		hst%hlth_voc_hist= 0 
		Ncol = size(drawi_ititer,2)
		al_int_it_endog  = al_it_int
		al_it_endog      = al_it

		if(shk%drawn /= 1 )then
			call draw_shocks(shk)
		endif		

		!set up cumpid,cumptau
		cumpid = 0.
		cumptau = 0.
		cumPrDage = 0.
		do idi=1,ndi
		do it =1,TT-1
			do id =1,nd
				do i =1,nd
					cumpid(id,i+1,idi,it) = pid(id,i,idi,it)+cumpid(id,i,idi,it)
				enddo
			enddo
		enddo
		enddo
		it = 1
		cumptau(it+1)=cumptau(it)
		do it =2,TT
			cumptau(it+1) = cumptau(it)+ptau(it)
		enddo
		do it =1,TT-1
			do id =1,nd
				cumPrDage(id+1,it) = PrDage(id,it) +cumPrDage(id,it)
			enddo
		enddo

		! will draw these from endogenous distributions the second time around
		d_it = 1
		a_it = agrid(1)
		a_it_int = 1
		e_it = egrid(1)
		e_it_int = 1
		status_it = 1 ! just to initialize on the first round 
		do i=1,Nsim
			do it=1,Tsim
				if(age_it(i,it)>=TT) status_it(i,it) = 5
				if(age_it(i,it)<= 0) status_it(i,it) = 0
			enddo
		enddo
		
		a_mean_liter = 0.
		d_mean_liter = 0.
		s_mean_liter = 0.
		a_var_liter  = 0.
		d_var_liter  = 0.

		tri = tri0
		
		if(verbose >2) print *, "Simulating"
		w_strchng_old = w_strchng
		w_strchng = .false.
		final_iter = .false.
		!itertate to get dist of asset/earnings correct at each age from which to draw start conditions 
		do iter=1,iter_draws
			if(verbose >3) print *, "iter: ", iter
			di_prob_it = 0.
			app_dif_it = 0.
			work_dif_it = 0.
			hst%hlthprob_hist = 0.
			hst%hlth_voc_hist= 0 
			!set prob alpha=1 for each z state.  Only works now for z_contin == .false.
			if(iter>1)then 
				PrAl1= 0._dp
				totpopz = 0._dp
				PrAl1St3 = 0._dp
				do zi_hr=1,nz
					do i=1,Nsim
						do it=2,Tsim
							if((z_jt_macroint(it)==zi_hr) .and. (age_it(i,it)>0 ).and. (status_it(i,it) <=3  .and. status_it(i,it)>0 ) ) then 
								totpopz(zi_hr) = totpopz(zi_hr) + 1._dp
								if(al_int_it_endog(i,it)==1) then
									PrAl1(zi_hr) = PrAl1(zi_hr)+1._dp
									if(status_it(i,it)==3) &
										& PrAl1St3(zi_hr) = PrAl1St3(zi_hr)+1._dp
								endif
							endif
						enddo!it
					enddo !i
					PrAl1St3(zi_hr) = PrAl1St3(zi_hr)/PrAl1(zi_hr)
					PrAl1(zi_hr) = PrAl1(zi_hr)/totpopz(zi_hr)
				enddo !zi_hr
			endif!iter>1
			it = 1
			nomatch = 0
			junk =0.
			do i =1,Nsim
				!for the population that is pre-existing in the first period , it=1 and age>0
				!need to draw these from age-specific distributions for iterations > 1
				if(age_it(i,it)>0) then
					!use status_it_innov(i,Tsim) to identify the d state, along with age of this guy
					do d_hr=1,nd
						if(health_it_innov(i,1) < cumPrDage(d_hr+1,age_it(i,it))) &
							& exit
					enddo

					if((iter>1) ) then
						do ii=1,Ncol
							drawi = drawi_ititer(i,ii)!iter-1
							drawt = drawt_ititer(i,ii)!iter-1
							if( d_it(drawi,drawt) .eq. d_hr .and. status_it(drawi,drawt)>0) then 
								status_it(i,it) = status_it(drawi,drawt)
								d_it(i,it) = d_it(drawi,drawt)
								a_it(i,it) = a_it(drawi,drawt)
								e_it(i,it) = e_it(drawi,drawt)
								e_it_int(i,it) = e_it_int(drawi,drawt)
								a_it_int(i,it) = a_it_int(drawi,drawt)
								exit
							elseif(ii==Ncol) then
								nomatch = nomatch+1
							endif
						enddo
					endif
					if( (iter==1) .or. ii >=Ncol ) then

						status_it(i,it) = 1
						d_it(i,it) = d_hr
						if(age_it(i,it)==1) then
							a_it_int(i,it) = 1
							a_it(i,it) = minval(agrid)
							e_it(i,it) = minval(egrid)
							e_it_int(i,it) = 1
						else
							a_it_int(i,it) = na/2
							a_it(i,it) = agrid(na/2)
							e_it(i,it) = egrid(ne/2)
							e_it_int(i,it) = ne/2
						endif
					endif
				endif
				
			enddo !i=1:Nsim
			
			if( verbose>0 .and. nomatch>0 ) print *, "did not find match for draw ", nomatch, " times"

			!$OMP  parallel do &
			!$OMP& private(i,del_hr,j_hr,status_hr,it,it_old,age_hr,al_hr,ali_hr,d_hr,e_hr,a_hr,ei_hr,ai_hr,z_hr,zi_hr,api_hr,tri_hr,apc_hr,ep_hr, &
			!$OMP& iiH, iiwt, ziwt,ziH,triwt,triH,il,fnd_hr, sep_hr, il_hr,cumval,jwt,wage_hr,al_last_invol,junk,app_dif_hr,work_dif_hr, &
			!$OMP& hlthprob,ii,sepi,fndi,invol_un,dead,status_tmrw) 
			do i=1,Nsim
				!fixed traits
	
				!set a j to correspond to the probabilities.  This will get overwritten if born
				j_hr = j_i(i)
				del_hr = del_i_int(i)
				fnd_hr = fndsep_i_int(i,1,:)
				sep_hr = fndsep_i_int(i,2,:)
				il_hr = fnd_hr(2)
				!initialize stuff
				it = 1
				it_old = 1
				invol_un = 0
				dead = .false.
				do it=1,Tsim
				if(age_it(i,it) > 0 ) then !they've been born 
					
					if((born_it(i,it) .eq. 1 .and. it> 1) ) then
					! no one is ``born'' in the first period, but look the same
					! draw state from distribution of age 1 
						!new borns:
						age_hr	= 1
						do d_hr=1,nd
							if(health_it_innov(i,1) < cumPrDage(d_hr+1,age_hr)) &
								& exit
						enddo
						if(iter ==1) then
							a_hr 	= minval(agrid)
							ei_hr	= 1
							e_hr 	= minval(egrid)
							ai_hr 	= 1
							status_hr = 1
							d_it(i,it) = d_hr
							a_it(i,it) = minval(agrid)
							e_it(i,it) = 0.
							e_it_int(i,it) = 1
							a_it_int(i,it) = 1
							status_it(i,it) = 1
						else
							do ii=1,Ncol
								drawi = drawi_ititer(i,ii)!iter-1
								drawt = drawt_ititer(i,ii)!iter-1
								if(age_it(drawi,drawt) .eq. 1 .and. d_it(drawi,drawt) .eq. d_hr & 
								&	.and. status_it(drawi,drawt)>0) then 

									d_it(i,it)		= d_hr
									a_it(i,it)      = a_it(drawi,drawt)
									e_it(i,it)      = e_it(drawi,drawt)
									e_it_int(i,it)  = e_it_int(drawi,drawt)
									a_it_int(i,it)  = a_it_int(drawi,drawt)
									status_it(i,it) = status_it(drawi,drawt)
									
									a_hr  = a_it(drawi,drawt)
									e_hr  = e_it(drawi,drawt)
									ei_hr = e_it_int(drawi,drawt)
									ai_hr  = a_it_int(drawi,drawt)
									status_hr = status_it(drawi,drawt)
									exit
								elseif(ii==Ncol) then
									a_hr 	= minval(agrid)
									ei_hr	= 1
									e_hr 	= minval(egrid)
									ai_hr 	= 1
									status_hr = 1
									d_it(i,it) = d_hr
									a_it(i,it) = minval(agrid)
									e_it(i,it) = 0.
									e_it_int(i,it) = 1
									a_it_int(i,it) = 1
									status_it(i,it) = 1
									nomatch = nomatch+1
								endif
							enddo
						endif !iter ==1

					else !already born, just load state - may have been set earlier in the iteration if they're born in the 1st period
						age_hr	= age_it(i,it)
						d_hr	= d_it(i,it)
						a_hr 	= a_it(i,it)
						ei_hr	= e_it_int(i,it)
						e_hr 	= e_it(i,it)
						ai_hr 	= a_it_int(i,it)
						status_hr = status_it(i,it)
						if(iter==1 .and. it==1 .and. age_hr< TT) then
							status_hr = 1 
							status_it(i,it) = 1
						endif
					endif !if make decisions when first born?
					
					! get set to kill off old (i.e. age_hr ==TT only for Longev - youngD - oldD*oldN )
					if((age_hr .eq. TT) ) then !
						it_old = it_old + 1
						if(it_old >  Tret ) then !
							dead = .true.
						else
							status_it(i,it) = 5
						endif
					endif 
					
					if(dieyoung .eqv. .true.)then
						if(status_it_innov(i,Tsim-it+1)< PrDeath(d_hr,age_hr)) & !this is using the back end of status: if it's very high, then dead
							dead = .true.
					endif
					
					if(dead .eqv. .true.) then
							!print *, 'DEAD!!!'
							!age_it(i,it) = -1 !if I change this, then I have to reset for the next iteration
							a_it(i,it) = 0.
							a_it_int(i,it) = 1
							d_it(i,it) = 1
							app_dif_it(i,it) = 0.						
							work_dif_it(i,it) = 0.
							status_it(i,it) = -1
							dead = .true.
							cycle
						!	exit
					endif

					!figure out where to evaluate z
					if(zj_contin .eqv. .false.) then
						zi_hr	= z_jt_macroint(it)
						z_hr	= zgrid(zi_hr,j_hr)
					else
						z_hr	= z_jt_panel(it,j_hr)
						do zi_hr = nz,1,-1
							if(zgrid(zi_hr,j_hr)<z_hr) exit
						enddo
						ziH  = min(zi_hr+1,nz)
						ziwt = (zgrid(ziH,j_hr)- z_hr)/( zgrid(ziH,j_hr) -   zgrid(zi_hr,j_hr) )
						if( ziH == zi_hr ) ziwt = 1.
					endif


					!set the idiosyncratic income state
					al_hr	= al_it(i,it)
					ali_hr	= al_it_int(i,it)
					if(invol_un .eq. 1 )then
						al_hr	= alfgrid(1)
						ali_hr	= 1
					endif

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!!RETURN TO THIS PART!
!!!!Setting the number of invol unemp in the first period
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
					!in the first period need to establish the right number of exog unemp
!~ 					if((it==1) .and. (iter>1) .and. (status_hr<=3) .and. (age_hr>0)) then
!~ 						if(status_it_innov(i,Tsim-1) < PrAl1(zi_hr)) then
!~ 							ali_hr = 1
!~ 							al_last_invol = al_hr
!~ 							invol_un = 1
!~ 							iiwt = 1._dp
!~ 							iiH = 2
!~ 							al_hr = alfgrid(ali_hr)
!~ 							if(status_it_innov(i,Tsim-2)<PrAl1St3(zi_hr)) then
!~ 								status_hr=3
!~ 								status_tmrw = 3
!~ 								status_it(i,it) = 3
!~ 							else 
!~ 								status_hr=2
!~ 								status_tmrw = 2
!~ 								status_it(i,it) = 2
!~ 							endif
!~ 						endif
!~ 					endif
					
					if( w_strchng .eqv. .true.) then
						do tri_hr = ntr,1,-1
							if( trgrid(tri_hr)<wage_trend(it,j_hr) ) &
							&	exit
							triH = min(tri_hr+1,ntr)
							if(triH>tri_hr) then
								triwt = (trgrid(triH)- wage_trend(it,j_hr))/(trgrid(triH) - trgrid(tri_hr))
							else
								triwt = 1._dp
							endif
						enddo
						wtr_it(i,it) = wage_trend(it,j_hr) 
					else
						tri_hr = tri0
						triwt = 1._dp
					endif

					!figure out where to evaluate alpha
					if(al_contin .eqv. .true.) then
						iiH  = max(1, min(ali_hr+1,nal))
						if(ali_hr>1) then 
							iiwt = (alfgrid(iiH)- al_hr)/( alfgrid(iiH) -   alfgrid(ali_hr) )
						else !unemp
							iiwt = 1._dp
						endif
						if( iiH == ali_hr ) iiwt = 1._dp
					endif

					junk = 0._dp
					if(w_strchng .eqv. .true.) junk = wage_trend(it,j_hr)
					wage_hr	= wage(wage_lev(j_hr)+junk,al_hr,d_hr,z_hr,age_hr)
					if(invol_un ==1) &
						& wage_hr	= wage(wage_lev(j_hr)+junk,al_last_invol,d_hr,z_hr,age_hr)
					hst%wage_hist(i,it) = wage_hr

					!make decisions if not yet retired
					if(age_hr < TT) then 
						!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						! evalutate gwork and gapp to figure out lom of status 
						if(status_hr .le. 3) then !in the labor force
							
							!check for rest unemployment
							if((al_contin .eqv. .true.) .and. (zj_contin .eqv. .false.) .and. (w_strchng .eqv. .false.)) then
								work_dif_hr = iiwt   *gwork_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) + &
										&	(1.-iiwt)*gwork_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr )
							elseif((al_contin .eqv. .true.) .and. (zj_contin .eqv. .true.) .and. (w_strchng .eqv. .false.)) then
								work_dif_hr = ziwt    * iiwt    *gwork_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) + &
										&	  ziwt    *(1.-iiwt)*gwork_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) + &
										&	 (1.-ziwt)* iiwt    *gwork_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,ziH  ,age_hr ) + &
										&	 (1.-ziwt)*(1.-iiwt)*gwork_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,ziH  ,age_hr )
							elseif((al_contin .eqv. .true.) .and. (zj_contin .eqv. .false.) .and. (w_strchng .eqv. .true.)) then
								work_dif_hr = triwt    * iiwt    *gwork_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) + &
										&	  triwt    *(1.-iiwt)*gwork_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) + &
										&	 (1.-triwt)* iiwt    *gwork_dif( (il_hr-1)*ntr + triH  , (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) + &
										&	 (1.-triwt)*(1.-iiwt)*gwork_dif( (il_hr-1)*ntr + triH  , (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr )
							else!if(al_contin .eqv. .false. ) then
								work_dif_hr = gwork_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr )
							endif
							work_dif_it(i,it) = work_dif_hr
							
							!draws for exog find and sep
							if( zj_contin .eqv. .true.) then
								fndi = ziwt*fndgrid(fnd_hr(zi_hr),zi_hr) + (1.-ziwt)*fndgrid(fnd_hr(ziH),ziH)
								sepi = ziwt*sepgrid(sep_hr(zi_hr),zi_hr) + (1.-ziwt)*sepgrid(sep_hr(zi_hr),zi_hr)
							else
								fndi = fndgrid(fnd_hr(zi_hr),zi_hr) !fndrate(zi_hr,j_hr)
								sepi = sepgrid(sep_hr(zi_hr),zi_hr)!seprisk(zi_hr,j_hr)
							endif
							
							
							! figure out status transition and involuntary unemployment
							select case (status_hr)
							case(1) ! working
								if( status_it_innov(i,it) < sepi) then !separate?
									ali_hr = 1
									invol_un = 1
									al_last_invol = al_hr
									wage_hr	= wage(wage_lev(j_hr),al_last_invol,d_hr,z_hr,age_hr)
									if(w_strchng .eqv. .true.) &
										& wage_hr	= wage(wage_lev(j_hr) + wage_trend(it,j_hr),al_last_invol,d_hr,z_hr,age_hr)
									iiwt = 1.
									iiH = 2
									al_hr = alfgrid(ali_hr)
									status_tmrw = 2
									status_it(i,it) = 2
								elseif( work_dif_hr<0) then
									status_tmrw = 2
									status_it(i,it) = 2
								else
									status_tmrw = 1
									status_it(i,it) = 1
								endif
							
							case(2) 
								! unemployed, may stay unemployed or become long-term unemployed
								if(status_it_innov(i,it) <=pphi) then
									status_tmrw = 3
									status_it(i,it) = 2	
									if( invol_un ==1 ) then
										ali_hr = 1
										al_hr = alfgrid(ali_hr)
										iiwt = 1.
										iiH = 2
									else 
										ali_hr	= al_it_int(i,it)
										al_hr = al_it(i,it)
									endif
								elseif( (invol_un == 1)  .and. (fndarrive_draw(i,it) > fndi)) then
								!voluntary or involuntary?
									ali_hr = 1
									al_hr = alfgrid(ali_hr)
									iiwt = 1.
									iiH = 2
									status_it(i,it) = 2
									status_tmrw =2
								elseif((invol_un == 1) .and. (fndarrive_draw(i,it) <= fndi)) then
									invol_un = 0
									ali_hr	= al_it_int(i,it)
									al_hr = al_it(i,it)
									! found a job!
									status_it(i,it)= 1
									status_tmrw = 1
								elseif( work_dif_hr < 0 ) then !voluntary unemployment (implies invol_un ==0)
									status_it(i,it) = 2
									status_tmrw = 2
								else ! invol_un != 1 and work_dif>0
									status_tmrw = 1
									status_it(i,it) = 1
									status_hr = 1
								endif
							case(3) ! status_hr eq 3
								!lfstatus updates
								if( (invol_un == 1)  .and. (fndarrive_draw(i,it) > lrho*fndi)) then
								!voluntary or involuntary?
									ali_hr = 1
									al_hr = alfgrid(ali_hr)
									iiwt = 1.
									iiH = 2
									status_it(i,it) = 3
									status_tmrw =3
								elseif((invol_un == 1) .and. (fndarrive_draw(i,it) <= lrho*fndi)) then
									invol_un = 0
									ali_hr	= al_it_int(i,it)
									al_hr = al_it(i,it)
									! found a job!
									status_it(i,it)= 3
									status_tmrw = 1
								elseif( work_dif_hr < 0 ) then !voluntary unemployment (implies invol_un ==0)
									status_it(i,it) = 3
									status_tmrw =3
								else ! invol_un != 1 and work_dif>0
									status_tmrw = 1
									status_it(i,it) = 3
									status_hr = 3
								endif
								
								!evaluate application choice
								if((al_contin .eqv. .true.) .and. (zj_contin .eqv. .false.) .and. (w_strchng .eqv. .false.)) then
									app_dif_hr = iiwt    *gapp_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) + &
											&	(1.-iiwt)*gapp_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr )
								elseif((al_contin .eqv. .true.) .and. (zj_contin .eqv. .true.) .and. (w_strchng .eqv. .false.) ) then
									app_dif_hr = ziwt    * iiwt    *gapp_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) + &
											&	 ziwt    *(1.-iiwt)*gapp_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) + &
											&	(1.-ziwt)*  iiwt   *gapp_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,ziH  ,age_hr ) + &
											&	(1.-ziwt)*(1.-iiwt)*gapp_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,ziH  ,age_hr ) 
								elseif((al_contin .eqv. .true.) .and. (zj_contin .eqv. .false.) .and. (w_strchng .eqv. .true.) ) then
									app_dif_hr = triwt    * iiwt    *gapp_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) + &
											&	 triwt    *(1.-iiwt)*gapp_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) + &
											&	(1.-triwt)*  iiwt   *gapp_dif( (il_hr-1)*ntr + triH  , (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) + &
											&	(1.-triwt)*(1.-iiwt)*gapp_dif( (il_hr-1)*ntr + triH  , (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) 
								else! if ((al_contin .eqv. .false.) .and. (zj_contin .eqv. .false.) ) then
									app_dif_hr = gapp_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr )
								endif
								
								app_dif_it(i,it) = app_dif_hr

								if( app_dif_hr < 0 ) app_it(i,it) = 0
								if(app_dif_hr >= 0) then
									! choose to apply
									app_it(i,it) = 1

									! eligible to apply?
									if( (age_hr > 1) .or. ((ineligNoNu .eqv. .false.) .and. (age_hr==1)) &
										& .or. ((age_hr ==1) .and. (status_it_innov(i,Tsim-it+1)<eligY) .and. (ineligNoNu .eqv. .true.) )) then !status_it_innov(i,it+1) is an independent draw
									
										!applying, do you get it?
										if(status_it_innov(i,it) < xifun(d_hr,trgrid(tri_hr),age_hr,hlthprob)) then 
											status_tmrw = 4
											if( status_it_innov(i,it) <  hlthprob) then
												hst%hlth_voc_hist(i,it) = 1
											else
												hst%hlth_voc_hist(i,it) = 2
											endif
										else	
											status_tmrw = 3
										endif
									else !not eligible
										app_it(i,it) = 0
										app_dif_it(i,it) =-1.
										status_tmrw = 3
									endif
									
								endif
								!record probabilities
								if( age_hr .eq. 1 .and. ineligNoNu .eqv. .true. ) then
									di_prob_it(i,it) = xifun(d_hr,wage_trend(it,j_hr),age_hr,hlthprob)*eligY
									hst%hlthprob_hist(i,it) = hlthprob*eligY
								else 	
									di_prob_it(i,it) = xifun(d_hr,wage_trend(it,j_hr),age_hr,hlthprob)
									hst%hlthprob_hist(i,it) = hlthprob
								endif
							end select
							
							if((status_hr <= 2) .or. (status_hr == 4)) then
								!evaluate application choice for diagnostics (would the workers want to apply? even if they can't)
								if((al_contin .eqv. .true.) .and. (zj_contin .eqv. .false.) .and. (w_strchng .eqv. .false.)) then
									app_dif_hr = iiwt    *gapp_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) + &
											&	(1.-iiwt)*gapp_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr )
								elseif((al_contin .eqv. .true.) .and. (zj_contin .eqv. .true.) .and. (w_strchng .eqv. .false.)) then
									app_dif_hr = ziwt    * iiwt    *gapp_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) + &
											&	 ziwt    *(1.-iiwt)*gapp_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) + &
											&	(1.-ziwt)*  iiwt   *gapp_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,ziH  ,age_hr ) + &
											&	(1.-ziwt)*(1.-iiwt)*gapp_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,ziH  ,age_hr ) 
								elseif((al_contin .eqv. .true.) .and. (zj_contin .eqv. .false.) .and. (w_strchng .eqv. .true.)) then
									app_dif_hr = triwt    * iiwt    *gapp_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) + &
											&	 triwt    *(1.-iiwt)*gapp_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) + &
											&	(1.-triwt)*  iiwt   *gapp_dif( (il_hr-1)*ntr + triH  , (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) + &
											&	(1.-triwt)*(1.-iiwt)*gapp_dif( (il_hr-1)*ntr + triH  , (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr ) 
								else! if((al_contin .eqv. .false.) .and. (zj_contin .eqv. .false.) ) then
									app_dif_hr = gapp_dif( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr )
								endif
								
								app_dif_it(i,it) = app_dif_hr
								!store the disability probability for the first group
								if( (age_hr > 1) .or. ((ineligNoNu .eqv. .false.) .and. (age_hr==1))) then
									di_prob_it(i,it) = xifun(d_hr,wage_trend(it,j_hr),age_hr,hlthprob)
								elseif( age_hr ==1)  then
									di_prob_it(i,it) = xifun(d_hr,wage_trend(it,j_hr),age_hr,hlthprob)*eligY
								endif
								
							endif
						
						elseif(status_hr > 3 ) then !absorbing states of D,R
							status_tmrw = status_hr
							! just to fill in values
							app_dif_it(i,it) = 0.
							work_dif_it(i,it) = 0.
							if(status_hr==4) di_prob_it(i,it) = 1.
							if( invol_un == 1) then
								ali_hr = 1
								al_hr = alfgrid(ali_hr)
							endif
						endif
						!evaluate the asset policy
						if(status_hr .eq. 4) then
							api_hr = aD( d_hr,ei_hr,ai_hr,age_hr )
							apc_hr = agrid(api_hr)
						elseif(status_hr .eq. 5) then ! should never be in this condition
							api_hr = aR(d_hr,ei_hr,ai_hr)
							apc_hr = agrid(api_hr)
						else
							!INTERPOLATE!!!!!	
							if((al_contin .eqv. .true.)  .and. (zj_contin .eqv. .false.) .and. (w_strchng .eqv. .false.)) then
								if(status_hr .eq. 1) then
									apc_hr = iiwt    *agrid( aw( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr  )) +&
										&	(1.-iiwt)*agrid( aw( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr  ))
								elseif(status_hr .eq. 2) then
									apc_hr = iiwt    *agrid( aU( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr )) +&
										&	(1.-iiwt)*agrid( aU( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr ))
								elseif(status_hr .eq. 3) then
									apc_hr = iiwt    *agrid( aN( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr )) +&
										&	(1.-iiwt)*agrid( aN( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr ))
								endif
								api_hr = 1
								do ii=2,na
									if( dabs(agrid(ii)-apc_hr) <  dabs(agrid(ii)-agrid(api_hr))) api_hr = ii
								enddo
								api_hr = min(max(ali_hr,1),na)
							elseif((al_contin .eqv. .true.)  .and. (zj_contin .eqv. .true.) .and. (w_strchng .eqv. .false.)) then
								if(status_hr .eq. 1) then
									apc_hr = ziwt    * iiwt    *agrid( aw( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr  )) +&
										&	 ziwt    *(1.-iiwt)*agrid( aw( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr  )) +&
										&	(1.-ziwt)* iiwt    *agrid( aw( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,ziH  ,age_hr  )) +&
										&	(1.-ziwt)*(1.-iiwt)*agrid( aw( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,ziH  ,age_hr  ))
								elseif(status_hr .eq. 2) then
									apc_hr = ziwt    * iiwt    *agrid( aU( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr )) +&
										&	 ziwt    *(1.-iiwt)*agrid( aU( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr )) +&
										&   (1.-ziwt)* iiwt    *agrid( aU( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,ziH  ,age_hr )) +&
										&	(1.-ziwt)*(1.-iiwt)*agrid( aU( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,ziH  ,age_hr ))
								elseif(status_hr .eq. 3) then
									apc_hr = ziwt    * iiwt    *agrid( aN( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr )) +&
										&	 ziwt    *(1.-iiwt)*agrid( aN( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr )) +&
										&   (1.-ziwt)* iiwt    *agrid( aN( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,ziH  ,age_hr )) +&
										&	(1.-ziwt)*(1.-iiwt)*agrid( aN( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,ziH  ,age_hr ))
								endif
								api_hr=1
								do ii=2,na
									if( dabs(agrid(ii)-apc_hr) <  dabs(agrid(ii)-agrid(api_hr))) api_hr = ii
								enddo
								api_hr = min(max(api_hr,1),na)
							elseif((al_contin .eqv. .true.)  .and. (zj_contin .eqv. .false.) .and. (w_strchng .eqv. .true.)) then
								if(status_hr .eq. 1) then
									apc_hr = triwt    * iiwt    *agrid( aw( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr  )) +&
										&	 triwt    *(1.-iiwt)*agrid( aw( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr  )) +&
										&	(1.-triwt)* iiwt    *agrid( aw( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr  )) +&
										&	(1.-triwt)*(1.-iiwt)*agrid( aw( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr  ))
								elseif(status_hr .eq. 2) then
									apc_hr = triwt    * iiwt    *agrid( aU( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr )) +&
										&	 triwt    *(1.-iiwt)*agrid( aU( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr )) +&
										&   (1.-triwt)* iiwt    *agrid( aU( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr )) +&
										&	(1.-triwt)*(1.-iiwt)*agrid( aU( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr ))
								elseif(status_hr .eq. 3) then
									apc_hr = triwt    * iiwt    *agrid( aN( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr )) +&
										&	 triwt    *(1.-iiwt)*agrid( aN( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr )) +&
										&   (1.-triwt)* iiwt    *agrid( aN( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr )) +&
										&	(1.-triwt)*(1.-iiwt)*agrid( aN( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+iiH   ,d_hr,ei_hr,ai_hr,zi_hr,age_hr ))
								endif
								api_hr=1
								do ii=2,na
									if( dabs(agrid(ii)-apc_hr) <  dabs(agrid(ii)-agrid(api_hr))) api_hr = ii
								enddo
								api_hr = min(max(api_hr,1),na)
							else !if((al_contin .eqv. .false.) .and. (zj_contin .eqv. .false.)) then
								if(status_hr .eq. 1) then
									api_hr = aw( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr  )
								elseif(status_hr .eq. 2) then
									api_hr = aU( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr )
								elseif(status_hr .eq. 3) then
									api_hr = aN( (il_hr-1)*ntr + tri_hr, (del_hr-1)*nal+ali_hr,d_hr,ei_hr,ai_hr,zi_hr,age_hr )
								endif
								apc_hr = agrid(api_hr)
							endif
						endif
					! retired
					elseif( (age_hr==TT) .and. (it_old <= Tret)) then
						api_hr      = aR( d_hr,ei_hr,ai_hr )
						apc_hr      = agrid(api_hr)
						status_hr   = 5
						status_tmrw = 5
						if(it<Tsim) &
						&	status_it(i,it+1) = status_hr
					endif
					
					al_int_it_endog(i,it) = ali_hr
					al_it_endog(i,it)     = al_hr
					!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
					!push forward the state:
					if(it<Tsim) then
						! push forward status
						status_it(i,it+1) = status_tmrw
						! push forward asset					
						a_it_int(i,it+1) = api_hr
						if( (al_contin .eqv. .true.) .or. (zj_contin .eqv. .true.) ) then
							a_it(i,it+1) = apc_hr
						else
							a_it(i,it+1) = agrid(api_hr) 
						endif
						!push forward AIME
						if(status_hr .eq. 1) then
							!here, it is continuous
							ep_hr = min( (e_hr*dble(it-1) + wage_hr)/dble(it),egrid(ne) )
							e_it(i,it+1) = ep_hr
							! assign to grid points by nearest neighbor
							! ei_hr = finder(egrid,e_it(i,it+1)) <- relatively short, but not thread safe
			! Random assingment?
!~ 							ei_hr = ne/2+1
!~ 							if( mod(i,3)==0 ) then
!~ 								ei_hr = 1
!~ 							elseif(mod(i,3)==1) then
!~ 								ei_hr = ne
								
!~ 							endif
!~ 							e_it_int(i,it+1) = ei_hr
							do ei_hr = ne,1,-1
								if( ep_hr < egrid(ei_hr) ) exit
							enddo
							ei_hr = max(ei_hr,1) !just to be sure we take base 1
							if(ei_hr < ne) then
								if( (ep_hr - egrid(ei_hr)) < (egrid(ei_hr+1) - ep_hr) ) then
									e_it_int(i,it+1) = ei_hr
								else
									e_it_int(i,it+1) = ei_hr + 1
								endif
							else
								e_it_int(i,it+1) = ne
							endif
						else
							e_it(i,it+1) = e_hr
							e_it_int(i,it+1) = ei_hr
						endif

						!push forward d 
						if(age_hr .lt. 6) then !if not retired 
							do ii=1,nd
								if(health_it_innov(i,it) < cumpid(d_hr,ii+1,del_hr,age_hr) ) then
									d_it(i,it+1) = ii
									exit
								endif
							enddo
						else 
							d_it(i,it+1) = d_hr
						endif
					endif
				else !age_it(i,it) <= 0, they've not been born or they are dead
					a_it(i,it) = 0.
					a_it_int(i,it) = 1
					d_it(i,it) = 1
					app_dif_it(i,it) = 0.						
					work_dif_it(i,it) = 0.
					status_it(i,it) = -1
				endif ! age_it(i,it)>0
				enddo !1,Tsim
			enddo! 1,Nsim
			!$OMP  end parallel do 
			if(print_lev >=3)then
				call vec2csv(val_hr_it,"val_hr.csv")
				call mat2csv (e_it,"e_it.csv")
				call mat2csv (a_it,"a_it.csv")
				call mati2csv(a_it_int,"a_it_int.csv")
				call mati2csv(status_it,"status_it.csv")
				call mati2csv(d_it,"d_it.csv")
			endif

			a_mean = 0.
			d_mean = 0.
			s_mean = 0.
			a_var = 0.
			d_var = 0.
			do age_hr = 1,TT-1
				junk = 1.
				do i=1,Nsim
					do it = 1,Tsim
						if( age_hr .eq. age_it(i,it) ) then
							a_mean(age_hr) = a_it(i,it)      + a_mean(age_hr)
							d_mean(age_hr) = d_it(i,it)      + d_mean(age_hr)
							s_mean(age_hr) = status_it(i,it) + s_mean(age_hr)
							junk = junk + 1._dp
						endif
					enddo
				enddo
				a_mean(age_hr) = a_mean(age_hr)/junk
				d_mean(age_hr) = d_mean(age_hr)/junk
				s_mean(age_hr) = s_mean(age_hr)/junk
				do i=1,Nsim
					do it = 1,Tsim
						if( age_hr .eq. age_it(i,it) .and. a_it(i,it)>0._dp) then
							a_var(age_hr) = (dlog(a_it(i,it)) - dlog(a_mean(age_hr)))**2 + a_var(age_hr)
							d_var(age_hr) = (d_it(i,it) - d_mean(age_hr))**2+ d_var(age_hr)
						endif
					enddo
				enddo
				a_var(age_hr) = a_var(age_hr)/junk
				d_var(age_hr) = d_var(age_hr)/junk
			enddo
			if( final_iter .eqv. .true. ) then 
				if(verbose > 2) print *, "prob al1" ,PrAl1(1), ",", PrAl1(2)
				exit
			endif
			simiter_dist(iter) = sum((a_mean - a_mean_liter)**2) +sum((s_mean - s_mean_liter)**2)
			if( (  sum((a_mean - a_mean_liter)**2)<simtol .and. ( sum((s_mean - s_mean_liter)**2)<simtol .or. sum((d_mean - d_mean_liter)**2) <simtol) ).or. &
			&	(iter .ge. iter_draws-1) ) then
				if(verbose >=2 ) then
					print *, "done simulating after convergence in", iter
					print *, "dif a mean, log a var",  sum((a_mean - a_mean_liter)**2), sum((a_var - a_var_liter)**2)
					! NOTE: this is not actually mean because it does not have demographic weights
					print *, "a mean, a var",  sum(a_mean), sum(a_var)
					print *, "dif d mean,     d var",  sum((d_mean - d_mean_liter)**2), sum((d_var - d_var_liter)**2)
					print *, "dif status mean",  sum((s_mean - s_mean_liter)**2)
					print *, "status mean", sum(s_mean)
					print *,  "-------------------------------"
				endif
				
				if( w_strchng_old .eqv. .true. ) then
					w_strchng = .true.
					final_iter = .true.
				else 
					exit
				endif
			else
				if(verbose >=4 .or. ((verbose >=2) .and. (mod(iter,10) == 0))) then
					print *, "iter:", iter
					print *, "dif a mean, log a var",  sum((a_mean - a_mean_liter)**2), sum((a_var - a_var_liter)**2)
					print *, "a mean, a var",  sum(a_mean), sum(a_var)
					print *, "dif d mean,     d var",  sum((d_mean - d_mean_liter)**2), sum((d_var - d_var_liter)**2)
					print *, "dif status mean",  sum((s_mean - s_mean_liter)**2)
					print *,  "-------------------------------"
				endif
			endif
			a_mean_liter = a_mean
			d_mean_liter = d_mean
			s_mean_liter = s_mean
			a_var_liter = a_var
			d_var_liter = d_var
		enddo! iter
		
		if( print_lev>=2) then
			call vec2csv(simiter_dist(1:iter), "simiter_dist.csv" )
		endif
		
		! calc occupation growth rates
		if(occaggs_hr) then
			if(verbose >2) print *, "calculating occupation growth rates"		
			it = 1
			Nworkt = 0. !labor force in first period are the ones "born" in the first period
			occsize_jt = 0.
			occgrow_jt = 0.
			occshrink_jt = 0.
			do i=1,Nsim
				if( (age_it(i,it) > 0) .and. (status_it(i,it) <= 2) .and. (status_it(i,it)>=1)) Nworkt = 1._dp + Nworkt
				do ij=1,nj
					if(j_i(i) == ij .and. age_it(i,it) >= 1 .and. status_it(i,it) == 1) &
						& occsize_jt(ij,it) = 1._dp+occsize_jt(ij,it)
				enddo
			enddo
			occsize_jt(:,it) = occsize_jt(:,it) / Nworkt

			!$omp parallel do private(it,Nworkt,i,ij,occgrow_hr,occsize_hr,occshrink_hr)
			do it = 2,Tsim
				Nworkt = 0.
				occgrow_hr   = 0.
				occshrink_hr = 0.
				occsize_hr   = 0.
				do i=1,Nsim
					if(((status_it(i,it) <= 2) .and. (status_it(i,it)>=1)) .and. (age_it(i,it) > 0) ) Nworkt = 1._dp + Nworkt !labor force in this period
					ij =j_i(i)
					if( born_it(i,it) == 1 ) &
						& occgrow_hr(ij) = 1._dp + occgrow_hr(ij)
					if( status_it(i,it-1) > 1  .and. status_it(i,it)== 1) &
						& occgrow_hr(ij) = 1._dp + occgrow_hr(ij) !wasn't working last period
					if(status_it(i,it-1) == 1 .and. status_it(i,it) > 1) &
						& occshrink_hr(ij) = 1._dp + occshrink_hr(ij)
					if(status_it(i,it) == 1) &
						& occsize_hr(ij) = 1._dp + occsize_hr(ij)
					
				enddo
				do ij =1,nj
					if( occsize_hr(ij) > 0._dp ) then
						occgrow_jt(ij,it) = occgrow_hr(ij)/occsize_hr(ij)
						occshrink_jt(ij,it) = occshrink_hr(ij)/occsize_hr(ij)
					else
						occgrow_jt(ij,it) = 0._dp
						occshrink_jt(ij,it) = 0._dp
					endif
				enddo
				occsize_jt(:,it) = occsize_hr/Nworkt
			enddo
			!$omp end parallel do
			
			if(print_lev > 1)then
					call mat2csv (e_it,"e_it_hist"//trim(caselabel)//".csv")
					call mat2csv (a_it,"a_it_hist"//trim(caselabel)//".csv")
					call mati2csv(a_it_int,"a_int_it_hist"//trim(caselabel)//".csv")
					call mati2csv(status_it,"status_it_hist"//trim(caselabel)//".csv")
					call mati2csv(d_it,"d_it_hist"//trim(caselabel)//".csv")
					call veci2csv(j_i,"j_i_hist"//trim(caselabel)//".csv")
					call veci2csv(z_jt_macroint,"z_jt_hist"//trim(caselabel)//".csv")
					call mat2csv (occsize_jt,"occsize_jt_hist"//trim(caselabel)//".csv")
					call mat2csv (occgrow_jt,"occgrow_jt_hist"//trim(caselabel)//".csv")
					call mat2csv (occshrink_jt,"occshrink_jt_hist"//trim(caselabel)//".csv")
					call mat2csv (hst%wage_hist,"wage_it_hist"//trim(caselabel)//".csv")
					call mat2csv (wtr_it,"wtr_it_hist"//trim(caselabel)//".csv")
					call mat2csv (hst%app_dif_hist,"app_dif_it_hist"//trim(caselabel)//".csv")
					call mat2csv (hst%di_prob_hist,"di_prob_it_hist"//trim(caselabel)//".csv")
					call mat2csv (hst%work_dif_hist,"work_dif_it_hist"//trim(caselabel)//".csv")
					call mati2csv(al_int_it_endog,"al_int_endog_hist"//trim(caselabel)//".csv")
					call mat2csv (al_it_endog,"al_endog_hist"//trim(caselabel)//".csv")
					call mati2csv (hst%hlth_voc_hist,"hlth_voc_hist"//trim(caselabel)//".csv")
					call mat2csv (hst%hlthprob_hist,"hlthprob_hist"//trim(caselabel)//".csv")
			endif
		endif
		
		deallocate(al_int_it_endog,al_it_endog)
		deallocate(e_it)
		deallocate(a_it_int,e_it_int)
		deallocate(app_it,work_it)
		deallocate(val_hr_it)
		deallocate(wtr_it)
		!deallocate(hlthvocSSDI)
		!deallocate(status_it_innov)
		!deallocate(drawi_ititer,drawt_ititer)

	end subroutine sim

end module sim_hists



!**************************************************************************************************************!
!**************************************************************************************************************!
!						Searches for parameters						       !
!**************************************************************************************************************!
!**************************************************************************************************************!
module find_params

	use V0para
	use helper_funs
	use sol_val
	use sim_hists
	use model_data

	implicit none

	integer :: mod_ij_obj, mod_it
	type(val_struct), pointer :: mod_vfs
	type(pol_struct), pointer :: mod_pfs
	type(hist_struct), pointer :: mod_hst
	type(shocks_struct), pointer :: mod_shk
	type(shocks_struct) :: glb_shk
	real(dp) :: mod_prob_target
	

	contains


	subroutine vscale_set(vfs, hst, shk, vscale_out)
		! this sets the scaling for vscale, which is necessary to do discrete choice over occuptions
		type(val_struct),intent(in) :: vfs
		type(hist_struct), intent(in):: hst
		type(shocks_struct), intent(in):: shk
		real(8)	:: vscale_out
		real(8)	:: cumval,updjscale,nborn
		integer  :: ij=1, i=1, it=1
		integer :: age_hr=1,d_hr=1,ai_hr=1,ali=1,ei_hr=1,idi=1, tri=1
		real(dp), allocatable :: j_val_ij(:,:)
		allocate(j_val_ij(Nsim,nj))
		cumval = 0.
		updjscale  = 0.1_dp
		j_val_ij = -1.e10_dp
		nborn = 0._dp
		vscale_out= 0._dp
		! use value functions for the first period alive
		
		tri = tri0
		it = 1
		do i = 1,Nsim
			if(shk%age_hist(i,it) > 0 ) then !they're alive in the first period
				nborn = 1._dp + nborn
				!set the state
				age_hr 	= 1
				d_hr 	= 1
				ai_hr	= 1
				ei_hr	= 1
				do ij = 1,nj
					j_val_ij(i,ij) = 0.
					do idi = 1,ndi ! expectation over delta
					do ali = 1,nal
						j_val_ij(i,ij) = vfs%V((ij-1)*ntr+tri,(idi-1)*nal+ali,d_hr,ei_hr,ai_hr, &
									& hst%z_jt_macroint(it),age_hr)*delwt(idi,ij)*ergpialf(ali) + j_val_ij(i,ij)
					enddo
					enddo
					vscale_out = dabs(j_val_ij(i,ij)) + vscale_out
					!print *, j_val_ij(i,ij)
				enddo
			endif
		enddo
		vscale_out = vscale/nborn/dble(nj)
		deallocate(j_val_ij)
	end subroutine vscale_set


	subroutine jshift_sol(vfs, hst, shk, probj_in, t0tT,jshift_out)
		! solves for the factors jshift(j)
		type(val_struct),intent(in) :: vfs
		type(hist_struct), intent(in):: hst
		type(shocks_struct), intent(in):: shk
		
		real(dp), intent(in) :: probj_in(:)
		integer,  intent(in) :: t0tT(:) ! should have the start and end periods during which people are born
		real(dp), intent(out):: jshift_out(:)
		real(dp) :: jshift_prratio=1.,cumval=1.,updjscale=1.,distshift=1.,ziwt=1.,z_hr=1.,nborn=0., al_hr=0.
		real(dp) :: jshift0(nj),pialf_conddist(nal)
		integer  :: ij=1, ik=1, iter=1
		integer :: age_hr=1,d_hr=1,ai_hr=1,ali=1,ali_hr=1, &
					& ei_hr=1,i=1,ii=1,idi=1, it=1, tri=1, ziH=1,zi_hr=1
		real(dp), allocatable :: j_val_ij(:,:)

		allocate(j_val_ij(Nsim,nj))

		cumval = 0.
		updjscale  = 0.1_dp
		jshift_out = 0._dp !initialize
		jshift0 = 0._dp
		j_val_ij = -1.e10_dp
		nborn = 0._dp

		tri = tri0
		! first load the value functions for the target period
		do it = t0tT(1), t0tT(2)
			do i = 1,Nsim
				if(shk%born_hist(i,it) > 0 .or.  ((it == 1) .and. (shk%age_hist(i,it) > 0)) ) then
				!they're alive in the first period or born this period
					nborn = 1._dp + nborn
					!set the state
					!ali_hr 	= shk%al_int_hist(i,it)
					age_hr 	= 1
					d_hr 	= 1
					ai_hr	= 1
					ei_hr	= 1
					do ij = 1,nj
						j_val_ij(i,ij) = 0.
						if(zj_contin .eqv. .true.)then
							z_hr	= hst%z_jt_panel(it,ij)
							zi_hr	= finder(zgrid(:,ij),z_hr)
							ziH  = min(zi_hr+1,nz)
							ziwt = (zgrid(ziH,ij)- z_hr)/( zgrid(ziH,ij) -   zgrid(zi_hr,ij) )
							if(ziH == zi_hr) ziwt=1.
						endif
						al_hr	= shk%al_hist(i,it)
						ali_hr	= shk%al_int_hist(i,it)
						if(w_strchng .eqv. .true.) then
							if(ali_hr>1) al_hr = max(al_hr + wage_trend(it,ij), alfgrid(2))
							do ali_hr = nal,2,-1
								if(alfgrid(ali_hr)<ali_hr) exit
							enddo
							if( (alfgrid( min(ali_hr+1,nal) )-al_hr < al_hr-alfgrid(ali_hr)) .and. (ali_hr <nal) ) ali_hr = ali_hr+1
						endif
						if(it==1 ) then
							pialf_conddist = ergpialf
						else
							pialf_conddist = pialf(ali_hr,:)
						endif
						do idi = 1,ndi ! expectation over delta and alpha
						do ali = 1,nal
							if(zj_contin .eqv. .true.) then
								j_val_ij(i,ij) =( ziwt    * vfs%V((ij-1)*ntr+tri,(idi-1)*nal+ali,d_hr,ei_hr,ai_hr,zi_hr,age_hr) &
										&	+	 (1.-ziwt)* vfs%V((ij-1)*ntr+tri,(idi-1)*nal+ali,d_hr,ei_hr,ai_hr,ziH  ,age_hr) ) &
										&	*  delwt(idi,ij)*pialf_conddist(ali) + j_val_ij(i,ij)
							else
								j_val_ij(i,ij) = vfs%V((ij-1)*ntr+tri,(idi-1)*nal+ali,d_hr,ei_hr,ai_hr, &
											& hst%z_jt_macroint(it),age_hr)*delwt(idi,ij)*pialf_conddist(ali) + j_val_ij(i,ij)
							endif
						enddo
						enddo
					enddo
				endif !born
			enddo !do i
		enddo !do it
		
		!iterate on shift_k to solve for it
		do iter=1,maxiter*nj
			distshift = 0._dp
			do ij=1,nj
				jshift_prratio = 0.
				do i =1,Nsim
					if(j_val_ij(i,ij) > -1.e9_dp) then
						cumval = 0.
						do ik=1,nj
							cumval = dexp( (j_val_ij(i,ik)+jshift0(ik))/(amenityscale*vscale) ) + cumval
						enddo
						jshift_prratio = dexp(j_val_ij(i,ij)/(amenityscale*vscale))/cumval + jshift_prratio
					endif
				enddo
				jshift_prratio = probj_in(ij)/jshift_prratio*nborn
				jshift_out(ij) = dlog(jshift_prratio)*amenityscale*vscale
				distshift = dabs(jshift_out(ij) - jshift0(ij)) + distshift
				jshift0(ij) = updjscale*jshift_out(ij) + (1._dp - updjscale)*jshift0(ij)
			enddo
			if (distshift<1.e-5_dp) then
				exit
			endif
		enddo
		call vec2csv(jshift0,"jshift0.csv")

		deallocate(j_val_ij)
		
	end subroutine

	
	subroutine comp_ustats(hst,shk,urt,udur,Efrt,Esrt)
		
		type(shocks_struct) :: shk
		type(hist_struct):: hst
		real(dp), intent(out) :: urt,udur,Efrt,Esrt
		real(dp) :: Nunemp,Nlf, Nsep,Nfnd
		integer :: i, j, it,duri
		
		udur = 0.
		urt  = 0.
		Nlf  = 0.
		Nunemp = 0.
		Nsep = 0.
		Nfnd = 0.
		do i = 1,Nsim
			duri = 0
			do it=1,Tsim
				if(hst%status_hist(i,it)<=2 .and. hst%status_hist(i,it)>0) then
					Nlf = Nlf+1.
					if(hst%status_hist(i,it) == 2) then
						Nunemp = Nunemp + 1.
						if(duri == 0 .and. it>1) & !count a new spell
							& Nsep = Nsep+1.
						duri = duri+1
						udur = dble(duri) + udur
					else 	
						if(duri >0) & !just found
							& Nfnd = Nfnd+1
						duri = 0
					endif
				endif
			enddo
		enddo
		urt = Nunemp/Nlf
		udur = udur/Nunemp
		Esrt = Nsep/(Nlf-Nunemp)
		Efrt = Nfnd/Nunemp
	
	end subroutine comp_ustats
	
	subroutine iter_wgtrend(vfs, pfs, hst,shk )

		type(shocks_struct) :: shk
		type(val_struct) :: vfs
		type(pol_struct) :: pfs
		type(hist_struct):: hst
		
		real(dp) :: dist_wgtrend,dist_wgtrend_iter(maxiter),dist_urt(maxiter),dist_udur(maxiter), sep_fnd_mul(maxiter,2)
		real(dp), allocatable :: jwages(:), dist_wgtrend_jt(:,:),med_wage_jt(:,:)
		real(dp) :: wage_trend_hr
		integer  :: i,ii,ij,it, iter,iout,plO,vO, ik, ip,ri
		real(dp) :: urt,udur,Efrt,Esrt
		real(dp) :: fndrt_mul0,fndrt_mul1,dur_dist0,seprt_mul0,seprt_mul1
		real(dp) :: avg_convergence, sep_implied
		integer  :: miniter = 3, status, Ncoef
		
		!for running/matching the wage regression:
		real(dp), allocatable :: XX(:,:), yy(:), coef_est(:), wage_coef(:),cov_coef(:,:), XX_ii(:,:), yy_ii(:)
		real(dp):: hatsig2
		
		
		Ncoef = (Nskill+1)*(NpolyT+1)+2 !NpolyT*Nskill + Nskill + NpolyT + 2 + const
		
		allocate(XX(Tsim*Nsim,Ncoef))
		allocate(yy(Tsim*Nsim))
		allocate(coef_est(Ncoef))
		allocate(wage_coef(Ncoef))
		allocate(cov_coef(Ncoef,Ncoef))
		
		allocate(jwages(Nsim))
		allocate(dist_wgtrend_jt(Tsim,nj))
		allocate(med_wage_jt(Tsim,nj))
		
		
		plO = print_lev
		if(plO<4) print_lev = 1
		vO = verbose
		if(vO<4) verbose=0
		!call mat2csv(wage_trend,"wage_trend_0.csv")
		avg_convergence = 1.

		!iniitialize wage_coef
		ri=1
		do ip=1,(NpolyT+1)
			do ik=1,(Nskill+1)
				wage_coef(ri) = occwg_coefs(ik,ip)
				ri = ri+1
			enddo !ik, skill
		enddo !ip, poly degree		

		!initialize fmul stuff
		fndrt_mul0 = 1. 
		seprt_mul0 = 1.
		
		do iter = 1,maxiter
			dist_wgtrend = 0.
			dist_wgtrend_iter(iter) = 0.
			
			call sim(vfs, pfs, hst,shk,.false.)
			
			call comp_ustats(hst,shk,urt,udur,Efrt,Esrt)
			if(verbose>2) print*,  'urt , udur', urt,udur !if(verbose>2) 
			if(verbose>2) print*,  'Efrt, Esrt', Efrt,Esrt
			dist_urt(iter) = (urt - avg_unrt)/avg_unrt
			dist_udur(iter)= (udur - avg_undur)/avg_undur
			
			ii = 0
			do i=1,Nsim
				do it=1,Tsim
					if(  (shk%age_hist(i,it) > 0) .and. (hst%status_hist(i,it)==1)) then
						ii = 1+ii
						ij = shk%j_i(i) !this guy's occupation
						yy(ii) = log(hst%wage_hist(i,it))
						ri=1
						do ip=1,(NpolyT+1)
							do ik=1,(Nskill+1)
								if(ik == 1 .and. ip == 1) then
									XX(ii,ri) = 1._dp
								elseif( ik==1 .and. ip>1) then
									XX(ii,ri) = (it/tlen)**(ip-1)
								else
									XX(ii,ri) = occ_onet(ij,ik-1)*(it/tlen)**(ip-1)
								endif
								ri = ri+1
							enddo !ik, skill
						enddo !ip, poly degree
						XX(ii,ri) = agegrid( shk%age_hist(i,it) )
						ri=ri+1
						XX(ii,ri) = agegrid( shk%age_hist(i,it) ) ** 2
						
					endif ! participating
				enddo !it
			enddo ! i
			
			allocate(XX_ii(ii,ri))
			allocate(yy_ii(ii))
			do i=1,ii
				XX_ii(i,:) = XX(i,:)
				yy_ii(i) = yy(i)
			enddo
			
			call OLS(XX_ii,yy_ii,coef_est,cov_coef, hatsig2, status)
			
			if( print_lev .ge. 3) then 
				call mat2csv(XX_ii, "XX_ii.csv")
				call vec2csv(yy_ii, "yy_ii.csv") 
				call vec2csv(coef_est, "coef_est.csv")
			endif
			
			deallocate(XX_ii,yy_ii)
			
			!compute distance in coefficient space
			dist_wgtrend = 0.
			ri=1
			do ip=1,(NpolyT+1)
				do ik=1,(Nskill+1)
					if(ik > 1 .or. ip > 1) then
						if((wglev_0 .eqv. .true.) .or. (ip .gt. 1)) then
							!distance
							dist_wgtrend = dabs((coef_est(ri) - occwg_coefs(ik,ip))/occwg_coefs(ik,ip)) + dist_wgtrend
							!update
							wage_coef(ri) = -upd_wgtrnd*(coef_est(ri) - occwg_coefs(ik,ip)) + wage_coef(ri)
						endif
					endif
					ri = ri+1
				enddo !ik, skill
			enddo !ip, poly degree
			if(wglev_0 .eqv. .true.) then
				dist_wgtrend = dist_wgtrend/(ri-1) !average across coefficients
			else 
				dist_wgtrend = dist_wgtrend/(ri-1-Nskill) !average across coefficients
			endif
			dist_wgtrend_iter(iter) = dist_wgtrend
			
			
			do ij=1,nj
				do it=1,Tsim
					wage_trend_hr = 0._dp
					do ip =1,(NpolyT+1)
						if((wglev_0 .eqv. .true.) .or. (ip .gt. 1)) then
							if(ip .gt. 1) &
							&	wage_trend_hr  = (dble(it)/tlen)**(ip-1)*wage_coef( (ip-1)*(Nskill+1)+1 )                   + wage_trend_hr
							do ik=2,(Nskill+1)
								wage_trend_hr  = (dble(it)/tlen)**(ip-1)*wage_coef( (ip-1)*(Nskill+1)+ik)*occ_onet(ij,ik-1) + wage_trend_hr
							enddo
						endif
					enddo
					
					wage_trend(it,ij) = wage_trend_hr !upd_wgtrnd*wage_trend_hr + (1._dp - upd_wgtrnd)*wage_trend(it,ij)					
				enddo
			enddo
			do i=1,nj
				if( wglev_0 .eqv. .false.) wage_lev(i) = wage_trend(1,i)
				wage_trend(:,i) = wage_trend(:,i) - wage_trend(1,i)
			enddo

			do ij=1,nj
			do it=1,Tsim

				if(wage_trend(it,ij) <= minval(trgrid)) then
					wage_trend(it,ij) = minval(trgrid)
				endif
				if(wage_trend(it,ij) >= maxval(trgrid)) then
					wage_trend(it,ij) = maxval(trgrid)
				endif

			enddo
			enddo
				
				

			if(iter>100) avg_convergence = dabs( sum(dist_wgtrend_iter(iter-100:iter))/100. - dist_wgtrend_iter(iter)) !in case not making progress
			if((dist_wgtrend_iter(iter)<simtol .and. iter>miniter) .or. avg_convergence<simtol) then !cannot get too close because also relies on sim converging
				exit
			endif

!~ 			if(print_lev .ge. 4) then
!~ 				if(iter==1) iout=0
!~ 				call mat2csv( dist_wgtrend_jt, "dist_wgtrend_jt.csv",iout)
!~ 				call mat2csv(med_wage_jt,"med_wage_jt.csv",iout)
!~ 				iout=1
				
!~ 			endif
			!take a step in fndrate, seprisk space
			
			fndrt_mul1 = udur/avg_undur*fndrt_mul0
			fndrt_mul1 = upd_wgtrnd*fndrt_mul1 + (1.-upd_wgtrnd)*fndrt_mul0

			sep_implied = (Efrt*avg_unrt)/(1.-avg_unrt)
!!!			separation rate search: this used bisection, but that makes other variables jump around
!~ 			if( urt - avg_unrt >0._dp ) then
!~ 				seprtH = upd_wgtrnd*seprt_mul1 + (1._dp - upd_wgtrnd)*seprtH
!~ 			else
!~ 				seprtL = upd_wgtrnd*seprt_mul1 + (1._dp - upd_wgtrnd)*seprtL
!~ 			endif
!~ 			seprt_mul1 = 0.5_dp*(seprtH + seprtL)

!!! 		separation rate search: gradient search. Step size is arbitrary.
			seprt_mul1 = seprt_mul0 - 0.01_dp*(urt - avg_unrt)/avg_unrt
			
			!seprisk = seprisk/seprt_mul0*seprt_mul1
			!fndrate = fndrate/fndrt_mul0*fndrt_mul1
			sepgrid = sepgrid/seprt_mul0*seprt_mul1
			fndgrid = fndgrid/fndrt_mul0*fndrt_mul1
			
			
			seprt_mul0 = seprt_mul1
			fndrt_mul0 = fndrt_mul1
			sep_fnd_mul(iter,:) = (/ seprt_mul1, fndrt_mul1/)
			
			if(verbose .ge. 3) &
				print*, "iter ", iter, "dist ", dist_wgtrend, "seprt1", seprt_mul1
			if(vO .ge. 2 .and. mod(iter,100)==0) then
				print*, "iter ", iter, "dist ", dist_wgtrend
			endif
		enddo !iter
		
		print_lev = plO
		verbose = vO
		!call mat2csv(wage_trend,"wage_trend_new.csv")
		!call vec2csv(dist_wgtrend_iter,"dist_wgtrend_iter.csv")
		if(print_lev .ge. 2) then 
			call mat2csv(wage_trend,"wage_trend_jt.csv")
			call vec2csv(wage_lev,"wage_lev_j.csv")
			call vec2csv(dist_wgtrend_iter(1:(iter-1)), "dist_wgtrend_iter.csv")
			call vec2csv(dist_urt(1:(iter-1)), "dist_urt.csv")
			call vec2csv(dist_udur(1:(iter-1)), "dist_udur.csv")
			call mat2csv(sep_fnd_mul(1:(iter-1),:), "sep_fnd_mul.csv")
			if(verbose .ge. 2) print *, "iterated ", (iter-1)
		endif
		
		
		deallocate(jwages,med_wage_jt,dist_wgtrend_jt)
		
		deallocate(XX,yy,coef_est,cov_coef)
		
		!compute median wage trends in each occupation using hst%wage_hist
	
	end subroutine iter_wgtrend


	subroutine cal_dist(paramvec, errvec,shk)
		! the inputs are the values of parameters we're moving in paramvec
		! the outputs are deviations from targets
		! 1/ persistence of occupation productivity shock
		! 2/ standard deviation of occupation productivity shock
		! 3/ dispersion of gumbel shock - amenityscale
		! 
		
		real(dp), intent(in) :: paramvec(:)
		real(dp), intent(out) :: errvec(:)
		
		type(shocks_struct) :: shk
		type(val_struct) :: vfs
		type(pol_struct) :: pfs
		type(hist_struct):: hst
		type(moments_struct):: moments_sim
		real(dp) :: jshift_hr(nj)
		real(dp) :: condstd_tsemp,totdi_rt,totapp_dif_hist,ninsur_app,napp_t,nu1,nu0
		integer :: ij=1,t0tT(2),it,i

		!zrho = paramvec(1)
		!zsig = paramvec(2)
		nu   = paramvec(1)
		if( size(paramvec)>1 ) &
		&	xizcoef = paramvec(2)
	
		call alloc_econ(vfs,pfs,hst)

		if(verbose >2) print *, "In the calibration"	

		! set up economy and solve it
		call set_zjt(hst%z_jt_macroint, hst%z_jt_panel, shk) ! includes call settfp()
		
		if(verbose >2) print *, "Solving the model"	
		call sol(vfs,pfs)

		if(j_rand .eqv. .false.) then 
			call vscale_set(vfs, hst, shk, vscale)
			if(dabs(vscale)<1) then 
				vscale = 1.
				if( verbose >1 ) print *, "reset vscale to 1"
			endif
			t0tT = (/1,1/)
			call jshift_sol(vfs, hst,shk, occsz0, t0tT, jshift(:,1)) !jshift_sol(vfs, hst, shk, probj_in, t0tT,jshift_out)
			if(j_regimes .eqv. .true.) then
				do it=2,Tsim
					if( mod(it,itlen*2)== 0 ) then
						t0tT = (/ it-itlen*2+1,   it/)
						call jshift_sol(vfs, hst,shk, occpr_trend(it,:) , t0tT,jshift_hr)
						do i=0,(itlen*2-1)
							do ij=1,nj
								jshift(ij,it-i) = jshift_hr(ij)*(1.- dble(i)/(tlen*2.-1)) + jshift(ij,it-itlen*2)*dble(i)/(tlen*2.-1)
							enddo
						enddo
					endif
				enddo
			else
				do it=2,Tsim
					jshift(:,it) = jshift(:,1)
				enddo
			endif
				
			if(print_lev>=1) call mat2csv(jshift,"jshift.csv")
		endif
		
		!I only want to iterate on the wage trend if I have a good set of parameters
		call iter_wgtrend(vfs, pfs, hst,shk)
		
		
		if(verbose >2) print *, "Simulating the model"	
		call sim(vfs, pfs, hst,shk)
		if(verbose >2) print *, "Computing moments"
		call moments_compute(hst,moments_sim,shk)
		if(verbose >0) print *, "DI rate" , moments_sim%avg_di
		
		
		
		condstd_tsemp = 0.
		do ij = 1,nj
			condstd_tsemp = moments_sim%ts_emp_coefs(ij+1) *occsz0(ij)+ condstd_tsemp
		enddo
		totapp_dif_hist = 0.
		ninsur_app = 0.
		do i =1,Nsim
			do it=1,Tsim
				if(hst%status_hist(i,it)<=3 .and. mod(it,itlen) .eq. 0) ninsur_app = 1.+ninsur_app ! only count the body once every year, comparable to data
				if(hst%status_hist(i,it)==3) &
				&	totapp_dif_hist = exp(10.*hst%app_dif_hist(i,it))/(1. + exp(10.*hst%app_dif_hist(i,it))) + totapp_dif_hist

			enddo
		enddo
		totapp_dif_hist = totapp_dif_hist/ninsur_app
		if(verbose >1) print *, "App rate (smooth)" , totapp_dif_hist
		
		ninsur_app = 0.
		napp_t = 0.
		moments_sim%init_di = 0._dp
		moments_sim%init_hlth_acc = 0._dp
		do it=itlen,(5*itlen)
			do i=1,Nsim
				if( hst%status_hist(i,it)<5 .and. hst%status_hist(i,it)>0 .and. shk%age_hist(i,it)>0) then
					if(hst%status_hist(i,it) == 4) moments_sim%init_di= moments_sim%init_di+1.
				!	smoothing number of DI applications:
					if(hst%status_hist(i,it) == 3) then
						if(hst%app_dif_hist(i,it)>(-100.) .and. hst%app_dif_hist(i,it)<100.) &
							moments_sim%init_di= moments_sim%init_di+dexp(smthELPM*hst%app_dif_hist(i,it))/(1.+dexp(smthELPM*hst%app_dif_hist(i,it)))*hst%di_prob_hist(i,it)
					endif
					ninsur_app = 1. + ninsur_app
					if( hst%hlth_voc_hist(i,it) >0) then
						napp_t = napp_t+1.
						if(hst%hlth_voc_hist(i,it)==1)  moments_sim%init_hlth_acc = moments_sim%init_hlth_acc+ 1. 
					endif
				endif
			enddo
		enddo
		moments_sim%init_di= moments_sim%init_di/ninsur_app
		if(napp_t > 0.) then
			moments_sim%init_hlth_acc= moments_sim%init_hlth_acc/napp_t
		else
			moments_sim%init_hlth_acc= 1._dp
		endif
		
		errvec(1) = (moments_sim%init_di - dirt_target)/dirt_target
		if(size(errvec)>1) &
		&	errvec(2) = (moments_sim%init_hlth_acc - hlth_accept)/hlth_accept
		
		call dealloc_econ(vfs,pfs,hst)

	end subroutine cal_dist

	subroutine cal_dist_nloptwrap(fval, nparam, paramvec, gradvec, need_grad, shk)

		integer :: nparam,need_grad
		real(8) :: fval, paramvec(nparam),gradvec(nparam)
		type(shocks_struct) :: shk
		real(8) :: errvec(nparam),paramwt(nparam),paramvecH(nparam),errvecH(nparam),paramvecL(nparam),errvecL(nparam),gradstep(nparam), fvalH,fvalL
		integer :: i, ii,print_lev_old, verbose_old
		
		
		print_lev_old = print_lev 
		verbose_old = verbose
		print_lev = 0
		verbose = 1

		
		if(verbose_old >=1) print *, "test parameter vector ", paramvec
		if(print_lev_old >=1) then
			open(unit=fcallog, file=callog ,ACCESS='APPEND', POSITION='APPEND')
			write(fcallog,*) "test parameter vector ", paramvec
		endif
		
		call cal_dist(paramvec, errvec,shk)

		if(verbose_old >=1) print *, "         error vector ", errvec
		if(print_lev_old >=1) then
			write(fcallog,*)  "         error vector ", errvec
			close(unit=fcallog)
		endif

		
		paramwt = 1./dble(nparam)		! equal weight
		fval = 0.
		do i = 1,nparam
			fval = errvec(i)**2*paramwt(i) + fval
		enddo
		if( need_grad .ne. 0) then
			do i=1,nparam
				gradstep (i) = min( dabs( paramvec(i)*(5.e-5_dp) ) ,5.e-5_dp)
				paramvecH(i) = paramvec(i) + gradstep(i)
				call cal_dist(paramvecH, errvecH,shk)	
				paramvecL(i) = paramvec(i) - gradstep(i)	
				call cal_dist(paramvecL, errvecL,shk)	
				fvalH = 0.
				fvalL = 0.
				do ii =1,nparam
					fvalH = paramwt(ii)*errvecH(ii)**2 + fvalH
					fvalL = paramwt(ii)*errvecL(ii)**2 + fvalL
				enddo
				gradvec(i) =  (fvalH - fvalL)/(2._dp * gradstep(i))
			enddo
			if(verbose_old >=1) print *, "             gradient ", gradvec
			if(print_lev_old >=1) then
				open(unit=fcallog, file=callog ,ACCESS='APPEND', POSITION='APPEND')
				write(fcallog,*) "             gradient ", gradvec
			endif
		endif
		print_lev = print_lev_old
		verbose = verbose_old	

	end subroutine cal_dist_nloptwrap


!	subroutine  dfovec(Nin,Nout,paramvec,errvec)
!		integer :: Nin, Nout
!		real(dp) :: paramvec(:), errvec(:)

		! need to get shk into here
		!call cal_dist(paramvec,errvec, shk)
		
!	end subroutine dfovec

end module find_params



!**************************************************************************************************************!
!**************************************************************************************************************!
!						MAIN DRIVER PROGRAM						       !
!**************************************************************************************************************!
!**************************************************************************************************************!

program V0main

	use V0para
	use helper_funs
	use sol_val
	use sim_hists
	use model_data
	use find_params !, only: cal_dist,iter_wgtrend,iter_zproc,jshift_sol,vscale_set

	implicit none


		
	!************************************************************************************************!
	! Counters and Indicies
	!************************************************************************************************!

		integer  :: id=1, it=1, ij=1, itr=1, ial=1, iz=1, i=1,j=1,narg_in=1, wo=1, idi, status=1,t0tT(2)
		character(len=32) :: arg_in
	!************************************************************************************************!
	! Other
	!************************************************************************************************!
		real(dp)	:: wagehere=1.,utilhere=1., junk=1., totapp_dif_hist,ninsur_app, param0(2)=1.,err0(2)=1.,cumpid(nd,nd+1,ndi,TT-1)
		real(dp)	:: jshift_hr(nj)
	!************************************************************************************************!
	! Structure to communicate everything
		type(val_struct), target :: vfs
		type(pol_struct), target :: pfs
		type(hist_struct):: hst
		type(shocks_struct) :: shk
		type(moments_struct):: moments_sim

		type(val_pol_shocks_struct) :: vfs_pfs_shk
		
	! Timers
		integer :: c1=1,c2=1,cr=1,cm=1
		real(dp) :: t1=1.,t2=1.
		logical :: sol_once = .true.
	! NLopt stuff
		integer(8) :: calopt=0,ires=0
		real(dp) :: lb(2),ub(2),parvec(2), ervec(2), erval,lb_1(1),ub_1(1),parvec_1(1),ervec_1(1)
!		external :: cal_dist_nloptwrap

		
		include 'nlopt.f'

	moments_sim%alloced = 0

	call setparams()
	
	narg_in = iargc()
	if( narg_in > 0 ) then
		call getarg(1, arg_in)
		print *, "initial nu=", arg_in
		read( arg_in, * ) nu
		if(narg_in > 1) then
			call getarg(2, arg_in)
			print *, "initial xiz=", arg_in
			read( arg_in, * ) xizcoef
		endif
	endif


	caselabel = ""
	agrid(1) = .05*(agrid(1)+agrid(2))
	if(print_lev >= 2) then
		! plot out a bunch of arrays for analyzing VFs, etc
		wo = 0
		call vec2csv(agrid,"agrid.csv",wo)
		call vec2csv(delgrid,'delgrid.csv',wo)
		call vec2csv(alfgrid,'alfgrid.csv',wo)
		call vec2csv(trgrid,'trgrid.csv',wo)
		call vec2csv(egrid,'egrid.csv',wo)
		call mat2csv(zgrid,'zgrid.csv',wo)
		call veci2csv(dgrid,'dgrid.csv',wo)
		call veci2csv(agegrid,'agegrid.csv',wo)		
		call mat2csv(piz(:,:),"piz.csv",wo)
		call mat2csv(pialf,"pial.csv",wo)
		call mat2csv(PrDeath,"PrDeath.csv",wo)
		cumpid = 0._dp
		do idi=1,ndi
		do it =1,TT-1
		do id =1,nd
			do i =1,nd
				cumpid(id,i+1,idi,it) = pid(id,i,idi,it)+cumpid(id,i,idi,it)
			enddo
		enddo
		enddo
		enddo
				
		wo=0
		do it = 1,TT-1
			do ij = 1,ndi
				call mat2csv(pid(:,:,ij,it),"pid.csv",wo)
				call mat2csv(cumpid(:,:,ij,it),"cumpid.csv",wo)
				
				if(wo==0) wo =1
			enddo
		enddo
		
		call vec2csv(occsz0, "occsz0.csv")
		call vec2csv(occdel, "occdel.csv")
		call mat2csv(prob_age, "prob_age.csv")
		call mat2csv(occpr_trend,"occpr_trend.csv")
		call mat2csv(occwg_trend,"occwg_trend.csv")
		call vec2csv(occwg_lev,"occwg_lev.csv")
		call mat2csv(occwg_coefs,"occwg_coefs.csv")


		open(1, file="wage_dist.csv")
		itr = tri0
		iz  = 3
		do it = 1,TT-1
			do ial =1,nal
				do id = 1,nd-1
					wagehere = wage(0._dp,alfgrid(ial),id,zgrid(iz,ij),it)
					write(1, "(G20.12)", advance='no') wagehere
!~ 					if(wagehere > maxwin) &
!~ 						maxwin = wagehere
!~ 					if(wagehere < minwin) &
!~ 						minwin = wagehere
				enddo
				id = nd
				wagehere = wage(0._dp,alfgrid(ial),id,zgrid(iz,ij),it)
				write(1,*) wagehere
			enddo
			write(1,*) " "! trailing space
		enddo	
		close(1)
		
		open(1, file="xi.csv")
		open(2, file="xi_hlth.csv")
		do it=1,TT-1
			do id=1,(nd-1)
				write(1, "(G20.12)", advance='no') xifun(id,minval(trgrid),it,junk)
				write(2, "(G20.12)", advance='no') junk
			enddo
			id = nd
			write(1,*) xifun(id,minval(trgrid),it,junk)
			write(2,*) junk
		enddo
		do it=1,TT-1
			do id=1,(nd-1)
				write(1, "(G20.12)", advance='no') xifun(id,maxval(trgrid),it,junk)
				write(2, "(G20.12)", advance='no') junk
			enddo
			id = nd
			write(1,*) xifun(id,maxval(trgrid),it,junk)
			write(2,*) junk
		enddo		
		close(1)
		close(2)

		open(1, file="util_dist.csv")
		junk =0.
		itr =tri0
		iz  =2
		do it = 1,TT-1
			do ial =1,nal
				do id = 1,nd-1
					wagehere = wage(0._dp,alfgrid(ial),id,zgrid(iz,ij),it)
					utilhere = util(wagehere,id,1)
					write(1, "(G20.12)", advance='no') utilhere
					junk = utilhere + junk
					utilhere = util(wagehere,id,2)
					write(1, "(G20.12)", advance='no') utilhere
					junk = utilhere + junk
					
				enddo
				id = nd
				utilhere = util(wagehere,id,1)
				write(1, "(G20.12)", advance='no') utilhere
				junk = utilhere + junk
				utilhere = util(wagehere,id,2)
				write(1, "(G20.12)", advance='yes') utilhere
				junk = utilhere + junk
			enddo
			write(1,*) " "! trailing space
		enddo	
		close(1)
	endif
	junk = junk/dble(2*nd*nal*(TT-1))
	!util_const = - junk - util_const
	

	if(verbose >2) then
		call system_clock(count_rate=cr)
		call system_clock(count_max=cm)
		call CPU_TIME(t1)
		call SYSTEM_CLOCK(c1)
	endif
	call alloc_shocks(shk)
	call draw_shocks(shk)
	call mat2csv(shk%status_it_innov,"status_it_innov"//trim(caselabel)//".csv")
	!************************************************************************************************!
	!solve it once
	!************************************************************************************************!
	if (sol_once .eqv. .true.) then
		call alloc_econ(vfs,pfs,hst)
		Vtol = 5e-5
		! set up economy and solve it

		call set_zjt(hst%z_jt_macroint, hst%z_jt_panel, shk) ! includes call settfp()
		
		if(verbose >1) print *, "Solving the model"	
		call sol(vfs,pfs)

		if(j_rand .eqv. .false.) then
			call vscale_set(vfs, hst, shk, vscale)
			if(dabs(vscale)<1) then 
				if( verbose >1 ) then 
					print *, "reset vscale to 1, vscale was ", vscale
				endif
				vscale = 1.
			endif
			if(verbose >2) print *, "solve for initial shift"
			t0tT= (/1,1/)
			call jshift_sol(vfs, hst,shk, occsz0, t0tT, jshift(:,1)) !jshift_sol(vfs, hst, shk, probj_in, t0tT,jshift_out)
			if(verbose >2) print *, "solve for second shift"
			if(j_regimes .eqv. .true.) then
				do it=2,Tsim
					if( mod(it,itlen*2)== 0 ) then
						t0tT = (/ it-itlen*2+1,   it/)
						call jshift_sol(vfs, hst,shk, occpr_trend(it,:) , t0tT,jshift_hr)
						do i=0,(itlen*2-1)
							do ij=1,nj
								jshift(ij,it-i) = jshift_hr(ij)*(1.- dble(i)/(tlen*2.-1)) + jshift(ij,it-itlen*2)*dble(i)/(tlen*2.-1)
							enddo
						enddo
					endif
				enddo
			else
				do it=2,Tsim
					jshift(:,it) = jshift(:,1)
				enddo
			endif	
			if(print_lev>=1) call mat2csv(jshift,"jshift"//trim(caselabel)//".csv")
		endif

		if(dbg_skip .eqv. .false.) then
			if(verbose>1) print *, "iterating to find wage trend"
			call iter_wgtrend(vfs, pfs, hst,shk)
		endif
		
		if(verbose >=1) print *, "Simulating the model"	
		call sim(vfs, pfs, hst,shk)
		if(verbose >=1) print *, "Computing moments"
		call moments_compute(hst,moments_sim,shk)
		if(verbose >0) print *, "DI rate" , moments_sim%avg_di
 
!	set mean wage:
		wmean = 0._dp
		junk = 0._dp
		do i=1,Nsim
			do it=1,Tsim
				wagehere = hst%wage_hist(i,it)
				if( wagehere > 0. ) then
					wmean = wagehere + wmean
					junk = junk+1.
				endif
			enddo
		enddo
		wmean = wmean/junk
		if(verbose >1) print *, "average wage:", wmean
			totapp_dif_hist = 0._dp
			ninsur_app = 0._dp
			do i =1,Nsim
				do it=1,Tsim
					if(hst%status_hist(i,it)<=3 .and. mod(it,itlen) .eq. 0) ninsur_app = 1.+ninsur_app ! only count the body once every year, comparable to data
					if(hst%status_hist(i,it)==3) &
					&	totapp_dif_hist = exp(10.*hst%app_dif_hist(i,it))/(1. + exp(10.*hst%app_dif_hist(i,it))) + totapp_dif_hist
				enddo
			enddo
			totapp_dif_hist = totapp_dif_hist/ninsur_app
		if(verbose >1) print *, "App rate (smooth)" , totapp_dif_hist

		Vtol = 1e-6

		if(dbg_skip .eqv. .false.) then
			parvec(1) = nu
			parvec(2) = xizcoef
			parvec_1(1) = nu
			err0 = 0.
			call cal_dist(parvec_1,ervec_1,shk)
			
			print *, ervec_1
		endif
		
		if(verbose > 2) then
			call CPU_TIME(t2)
			call SYSTEM_CLOCK(c2)
			print *, "System Time", dble(c2-c1)/dble(cr)
			print *, "   CPU Time", (t2-t1)
		endif
	endif !sol_once

	lb = (/0.001_dp, 0.0_dp/)
	ub = (/ 1._dp, 0.5_dp /)
	
!~ 	!set up the grid over which to check derivatives 
!~ 	open(unit=fcallog, file="cal_square.csv")
!~ 	write(fcallog,*) nu, xizcoef, ervec
!~ 	close(unit=fcallog)
!~ 	do i=1,10
!~ 	do j=1,10
!~ 		verbose=1
!~ 		print_lev =1
!~ 		open(unit=fcallog, file = "cal_square.csv" ,ACCESS='APPEND', POSITION='APPEND')
!~ 		parvec(1) = lb(1)+  (ub(1)-lb(1))*dble(i-1)/9._dp
!~ 		parvec(2) = lb(2)+  (ub(2)-lb(2))*dble(j-1)/9._dp
		
!~ 		call cal_dist(parvec,ervec,shk)
!~ 		write(fcallog, "(G20.12)", advance='no')  nu
!~ 		write(fcallog, "(G20.12)", advance='no')  xizcoef
!~ 		write(fcallog, "(G20.12)", advance='no')  ervec(1)
!~ 		write(fcallog, "(G20.12)", advance='yes') ervec(2)
!~ 		print *, nu, xizcoef, ervec(1), ervec(2)
!~ 		close(unit=fcallog)
!~ 	enddo
!~ 	enddo
	
	
!~ 	if( dbg_skip .eqv. .false.) then
!~ 		call nlo_create(calopt,NLOPT_LN_SBPLX,2)
!~ 	! 	call nlo_create(calopt,NLOPT_LN_SBPLX,1)
!~ 	! 	lb_1 = (/.01/)
!~ 		call nlo_set_lower_bounds(ires,calopt,lb)
!~ 	! 	ub_1 = (/5./)
!~ 		call nlo_set_upper_bounds(ires,calopt,ub)
!~ 		call nlo_set_xtol_abs(ires, calopt, 0.001_dp) !integer problem, so it is not very sensitive
!~ 		call nlo_set_ftol_abs(ires,calopt, 0.0005_dp)  ! ditto 
!~ 		call nlo_set_maxeval(ires,calopt,500_dp)
		
!~ 		call nlo_set_min_objective(ires, calopt, cal_dist_nloptwrap, shk)
		
!~ 		parvec(1) = nu
!~ 		parvec(2) = xizcoef
		!parvec_1(1) = nu

!~ 		open(unit=fcallog, file=callog)
!~ 		write(fcallog,*) " "
!~ 		close(unit=fcallog)
!~ 		call nlo_optimize(ires, calopt, parvec, erval)
!~ 		nu = parvec(1) ! new optimum
!~ 		xizcoef = parvec(2)

!~ 		call cal_dist(parvec_1,ervec_1,shk)
!~ 	endif

!~ !****************************************************************************
!~ !   Now run some experiments:

	! without wage trend
!~ 	caselabel = "wchng0"
!~ 	print *, caselabel, " ---------------------------------------------------"
!~ 	w_strchng = .false.
!~ 	del_by_occ = .true.
!~ 	demog_dat  = .true.
!~ 	!call cal_dist(parvec,err0,shk)
!~ 	if(verbose >2) print *, "Simulating the model"	
!~ 	call sim(vfs, pfs, hst,shk)
!~ 	if(verbose >2) print *, "Computing moments"
!~ 	call moments_compute(hst,moments_sim,shk)
!~ 	if(verbose >0) print *, "DI rate" , moments_sim%avg_di
!~ 	print *, "---------------------------------------------------"

!~ 	! without the correlation between delta and occupation
!~ 	del_by_occ = .false.
!~ 	w_strchng = .true.
!~ 	demog_dat = .true.
!~ 	caselabel = "deloc0"
!~ 	print *, caselabel, " ---------------------------------------------------"
!~ 	call set_age(shk%age_hist, shk%born_hist, shk%age_draw)
!~ 	call set_deli( shk%del_i_int,shk%del_i_draw,shk%j_i)
!~ 	if(verbose >2) print *, "Simulating the model"	
!~ 	call sim(vfs, pfs, hst,shk)
!~ 	if(verbose >2) print *, "Computing moments"
!~ 	call moments_compute(hst,moments_sim,shk)
!~ 	if(verbose >0) print *, "DI rate" , moments_sim%avg_di
!~ 	print *, "---------------------------------------------------"
	
	! without either the correlation between delta and occupation or wage trend
!	del_by_occ = .false.
!	w_strchng = .false.
!	demog_dat = .true.
!	caselabel = "wchng0deloc0"
!	print *, caselabel, " ---------------------------------------------------"
!	call set_age(shk%age_hist, shk%born_hist, shk%age_draw)
!	call set_deli( shk%del_i_int,shk%del_i_draw,shk%j_i)
!	if(verbose >2) print *, "Simulating the model"	
!	call sim(vfs, pfs, hst,shk)
!	if(verbose >2) print *, "Computing moments"
!	call moments_compute(hst,moments_sim,shk)
!	if(verbose >0) print *, "DI rate" , moments_sim%avg_di
!	print *, "---------------------------------------------------"
	
!	del_by_occ = .true.
!	w_strchng = .true.
!	demog_dat = .false.
!	caselabel = "demog0"
!	print *, caselabel, " ---------------------------------------------------"
!	call set_age(shk%age_hist, shk%born_hist, shk%age_draw)
!	call set_deli( shk%del_i_int,shk%del_i_draw,shk%j_i)
!	if(verbose >2) print *, "Simulating the model"	
!	call sim(vfs, pfs, hst,shk)
!	if(verbose >2) print *, "Computing moments"
!	call moments_compute(hst,moments_sim,shk)
!	if(verbose >0) print *, "DI rate" , moments_sim%avg_di
!	print *, "---------------------------------------------------"
	
!	del_by_occ = .true.
!	w_strchng = .false.
!	demog_dat = .false.
!	caselabel = "wchng0demog0"
!	print *, caselabel, " ---------------------------------------------------"
!	call set_age(shk%age_hist, shk%born_hist, shk%age_draw)
!	call set_deli( shk%del_i_int,shk%del_i_draw,shk%j_i)
!	if(verbose >2) print *, "Simulating the model"	
!	call sim(vfs, pfs, hst,shk)
!	if(verbose >2) print *, "Computing moments"
!	call moments_compute(hst,moments_sim,shk)
!	if(verbose >0) print *, "DI rate" , moments_sim%avg_di
!	print *, "---------------------------------------------------"

!	del_by_occ = .false.
!	w_strchng = .true.
!	demog_dat = .false.
!	caselabel = "deloc0demog0"
!	print *, caselabel, " ---------------------------------------------------"
!	call set_age(shk%age_hist, shk%born_hist, shk%age_draw)
!	call set_deli( shk%del_i_int,shk%del_i_draw,shk%j_i)
!	if(verbose >2) print *, "Simulating the model"	
!	call sim(vfs, pfs, hst,shk)
!	if(verbose >2) print *, "Computing moments"
!	call moments_compute(hst,moments_sim,shk)
!	if(verbose >0) print *, "DI rate" , moments_sim%avg_di
!	print *, "---------------------------------------------------"

!	del_by_occ = .false.
!	w_strchng = .false.
!	demog_dat = .false.
!	caselabel = "wchng0deloc0demog0"
!	print *, caselabel, " ---------------------------------------------------"
!	call set_age(shk%age_hist, shk%born_hist, shk%age_draw)
!	call set_deli( shk%del_i_int,shk%del_i_draw,shk%j_i)
!	if(verbose >2) print *, "Simulating the model"	
!	call sim(vfs, pfs, hst,shk)
!	if(verbose >2) print *, "Computing moments"
!	call moments_compute(hst,moments_sim,shk)
!	if(verbose >0) print *, "DI rate" , moments_sim%avg_di
!	print *, "---------------------------------------------------"
	
	
!~ 	!****************************************************************************!
!~ 	! IF you love something.... 
!~ 	!****************************************************************************!
	
	call nlo_destroy(calopt)
	call dealloc_shocks(shk)
	
	call dealloc_econ(vfs,pfs,hst)
	

!    .----.   @   @
!   / .-"-.`.  \v/
!   | | '\ \ \_/ )
! ,-\ `-.' /.'  /
!'---`----'----'

End PROGRAM


