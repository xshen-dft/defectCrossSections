module capcs
  
  use constants, only: dp, HartreeToJ

  implicit none 
  real(kind=dp),parameter :: Kb =  1.38064852d-23
  real(kind=dp),parameter :: pi= 3.14159265358979
  real(kind=dp),parameter :: tpi = 6.2831853071795864769 
  real(kind=dp),parameter :: Thz = 1.0d12
  real(kind=dp),parameter :: hbar = 1.0545718d-34
  real(kind=dp),parameter :: eV = 1.6021766208d-19
  real(kind=dp),parameter :: meV =  1.6021766208d-22
  real(kind=dp),parameter :: q_comvert = 3.920205055d50


  integer :: iBandIinit, iBandIfinal, iBandFinit, iBandFfinal
    !! Energy band bounds for initial and final state

  real(kind=dp), allocatable :: EDelta(:,:)
    !! Energy for delta function
  real(kind=dp), allocatable :: maxtrixElement(:,:)
    !! Electronic matrix element

  character(len=300) :: EInput
    !! Path to energy table to read
  character(len=300) :: M0Input
    !! Path to zeroth-order matrix element file
    !! `allElecOverlap.isp.ik`
  character(len=300) :: SjInput
    !! Path to Sj.out file


  real(kind=dp),allocatable :: ipfreq(:),Sj(:)
  real(kind=dp) :: temperature,beta
  real(kind=dp) :: limit,alpha,dstep,bin,gamma0, Eif, ematrix_real, ematrix_img, lambda
  complex(kind=dp) ::  G1t, wif,wif0,wif1
  character(len=256) :: dummy
  integer :: nstep, nw, nfreq, nn, nE

  namelist /capcsconf/ iBandIinit, iBandIfinal, iBandFinit, iBandFfinal, EInput, M0input, SjInput, &
                        temperature, nn, limit, gamma0, alpha, dstep, nw, bin, ematrix_real, ematrix_img

contains
subroutine init()
implicit none
character(len=256) :: dummy
open(13,file='input.in')
!read input
read(13,capcsconf)
beta = 1.0d0/Kb/temperature
bin = bin*meV
end subroutine

!----------------------------------------------------------------------------
  subroutine readEnergy(EDelta)
  
    implicit none

    ! Output variables:
    real(kind=dp), allocatable, intent(out) :: EDelta(:,:)
      !! Energy for delta function

    ! Local variables:
    integer :: _iBandIinit, _iBandIfinal, _iBandFinit, _iBandFfinal
      !! Band bounds from energy table
    integer :: iDum
      !! Dummy integer
    integer :: ibi, ibf
      !! Loop indices

    logical :: abortExecution
      !! If the program should end


    open(12,file=trim(EInput))

    read(12,*)
    read(12,*) iDum, _iBandIinit, _iBandIfinal, _iBandFinit, _iBandFfinal
      ! @todo Test these values against the input values
      

    allocate(EDelta(iBandIinit:iBandIfinal,iBandFinit:iBandFfinal))

    do ibf = iBandFinit, iBandFfinal
      do ibi = iBandIinit, iBandIfinal

        read(12,*) iDum, iDum, EDelta(ibi,ibf) ! in Hartree

      enddo
    enddo

    EDelta(:,:) = EDelta(:,:)*HartreeToJ

    close(12)

    return

  end subroutine readEnergy

!----------------------------------------------------------------------------
  subroutine readMatrixElement(matrixElement)

    implicit none

    ! Output variables:
    real(kind=dp), allocatable, intent(out) :: maxtrixElement(:,:)
      !! Electronic matrix element

    ! Local variables:
    integer :: _iBandIinit, _iBandIfinal, _iBandFinit, _iBandFfinal
      !! Band bounds from energy table
    integer :: iDum
      !! Dummy integer
    integer :: ibi, ibf
      !! Loop indices

    real(kind=dp) :: rDum
      !! Dummy real

    open(12,file=trim(M0Input))

    read(12,*)
    read(12,*) iDum, _iBandIinit, _iBandIfinal, _iBandFinit, _iBandFfinal
      ! @todo Test these values against the input values
      

    allocate(matrixElement(iBandIinit:iBandIfinal,iBandFinit:iBandFfinal))

    do ibf = iBandFinit, iBandFfinal
      do ibi = iBandIinit, iBandIfinal

        read(12,*) iDum, iDum, rDum, rDum, rDum, matrixElement(ibi,ibf) ! in Hartree^2

      enddo
    enddo

    matrixElement(:,:) = matrixElement(:,:)*HartreeToJ**2

    close(12)

    return

  end subroutine readMatrixElement

!----------------------------------------------------------------------------
subroutine readphonon()
implicit none
integer :: ifreq, modeIndex
open(12,file=trim(SjInput))
read(12,*)nfreq
!read mode number
allocate(Sj(1:nfreq))
allocate(ipfreq(1:nfreq))

do ifreq=1,nfreq
   read(12,*)modeIndex,Sj(ifreq),ipfreq(ifreq) !freq read from Sj.out is f(in Thz)*2pi
end do
!read frequency and Sj
ipfreq=ipfreq*Thz!*tpi convert to Hz*2pi
!transform frequency to Hz
close(12)
!write(*,*) "Frequency Read"
end subroutine

end module capcs



function G0_t(inputt) result(G0t) 
use capcs
  integer :: ifreq
  real(kind=dp) :: inputt, nj, omega, e_factor
  complex(kind=dp) G0t, tmp1, tmp2
  tmp1 = 0.0_dp
  tmp2 = 0.0_dp
  do ifreq=1, nfreq
   omega=ipfreq(ifreq)
   nj=1/(exp(hbar*omega*beta)-1)
   tmp1=tmp1+(nj+1)*Sj(ifreq)*exp(cmplx(0.0,omega*inputt,dp))+nj*Sj(ifreq)*exp(cmplx(0.0,-omega*inputt,dp))-(2*nj+1)*Sj(ifreq)
   !tmp2=tmp2+(nj+1)*Sj(ifreq)/e_factor*exp(cmplx(0.0,omega*inputt,dp))+nj*Sj(ifreq)*e_factor*exp(cmplx(0.0,-omega*inputt,dp))-(2*nj+1)*Sj(ifreq)
  end do
  G0t= tmp1! - exp(tmp2)
!time-dependent line-shape-function, expand it to the first order of Sj, you will get familiar form with Huang-Rhys factor
  !!G0t=G0t*exp(-0.25*(alpha*inputt)**2)
  !narrow Gaussian to simulate delta function, what we care about is the area, we make it narrow so neighboring LSF do not interfere
end function

function sinc(x) result (sincx)
use capcs
    real(kind=dp) :: x, sincx
    if ( x < 1e-20 ) then 
        sincx = 1.0_dp
    else
        sincx = sin(x)/x
    end if
end function

function intg(a, b, c, d, t, dt, tmpa2, tmpb2) result (res)
use capcs
    real(kind=dp) :: t, dt!t1, wt1, omega
    complex(kind=dp) :: res, a, b, c, d, tmpa2, tmpb2!,t2, t3, wt2, wt3, A, A1, A2, tmp
    !res = c*exp(b*t)+d/b*(b*t-1)*exp(b*t)
    res = (c+d/b*(b*t-1))*tmpb2
    !write(*,*) c,b,t
    t = t-dt
    !res = res - (c*exp(b*t)+d/b*(b*t-1)*exp(b*t))
    res = res - (c+d/b*(b*t-1))*tmpa2
    res = res/b
    !res = exp(a-zlog(b))
    !res = res*exp(a)/b 
end function

program captureCS
  use capcs
  use OMP_LIB

  implicit none

  ! Local variables:
  integer :: iTime
    !! Loop index

  integer :: j,k,numofcores
  real(kind=dp) :: rangemax, dtime, dw, inputt, t1, t2, inta, intb, S1, S2, sinc
  complex(kind=dp) :: temp,tmpa1,tmpa2,G0_t,tmpb1,tmpb2, intg, fa, fb, fc, fd, tmpa3, tmpb3
  real(kind=dp)::omega_tmp
  real(kind=dp),allocatable :: S(:)


  call init()
  call readphonon()
  call readEnergy(EDelta)
  call readMatrixElement(matrixElement)

  allocate(S(1:nE))
  S = 0.0d0

  !!limit = 1e-4
  dtime = 1/Thz
  write(*,*)"simps"
  write(*,*)dstep
  dstep = dtime*dstep

  gamma0 = gamma0*meV/hbar
  
  nstep=200000000!Ceiling(rangemax/dstep)
  write(*,*) nstep*dstep

  S1=0.0d0!+Real(ematrixif*exp(G0_t(inputt)+cmplx(0.0,inputt*EE/hbar,dp)-gamma0*inputt*inputt))*dstep

!$OMP PARALLEL DO default(shared) private(inputt,t1,t2,S2,iTime,j,k,omega_tmp,tmpa1,tmpa2,tmpa3,tmpb1,tmpb2,tmpb3)&
& firstprivate(Eif,inta,dstep,nw,dw,nstep) reduction(+:S1,S) 
  do iTime = 1, nstep-1, 2!nstep-1, 0, -1
    inputt=(float(iTime))*dstep

    t1=inputt + nstep*dstep*nn
    tmpa1 = (ematrixif)
    tmpa2 = G0_t(t1)-gamma0*t1 ! Lorentz

    t2 = t1 + dstep
    tmpb1 = (ematrixif)
    tmpb2 = G0_t(t2)-gamma0*t2 ! Lorentz

    do j = 1, nE
      Eif = EDelta(j)
      tmpa3 = tmpa2+cmplx(0.0,t1*Eif/hbar,dp)
      tmpb3 = tmpb2+cmplx(0.0,t2*Eif/hbar,dp)
      S(j) = S(j) + Real(4d0*tmpa1*exp(tmpa3)+2d0*tmpb1*exp(tmpb3))
    enddo
  enddo

  do i = 1, nE
     Eif = EDelta(i)
     t1 = nstep*dstep*nn
     t2 = (float(nstep))*dstep+nstep*dstep*nn
     S(i) = S(i) + Real(ematrixif*exp(G0_t(t1)+cmplx(0.0,t1*Eif/hbar,dp)-gamma0*t1)) ! Lorentz
     S(i) = S(i) - Real(ematrixif*exp(G0_t(t2)+cmplx(0.0,t2*Eif/hbar,dp)-gamma0*t2)) ! Lorentz
     S(i) = S(i)*2.0d0/3.0d0*dstep
     S(i) = S(i)/hbar/hbar
     write(*,'(f10.5,f7.1,i5,ES35.14E3)') EDelta(i)/eV, temperature, nn, S(i)
  END DO

end program
