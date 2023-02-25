module wfcExportVASPMod
  
  use constants, only: dp, iostd, angToBohr, eVToRy, ryToHartree, pi, twopi
  use mpi

  implicit none

  ! Parameters:
  integer, parameter :: root = 0
    !! ID of the root node
  integer, parameter :: mainOutFileUnit = 50
    !! Main output file unit
  integer, parameter :: potcarUnit = 71
    !! POTCAR unit for I/O
  integer, parameter :: nonlPseudoGridSize = 100
    !! Size of non-local pseudopotential grid
  integer, parameter :: wavecarUnit = 72
    !! WAVECAR unit for I/O

  real(kind = dp), parameter :: twoPiSquared = (2.0_dp*pi)**2
    !! This is used in place of \(2\pi/a\) which assumes that \(a=1\)


  ! Global variables not passed as arguments:
  integer :: ierr
    !! Error returned by MPI
  integer, allocatable :: iGkEnd_pool(:)
    ! Ending index for G+k vectors on
    ! single process in a given pool
  integer, allocatable :: iGkStart_pool(:)
    ! Starting index for G+k vectors on
    ! single process in a given pool
  integer :: ikEnd_pool
    !! Ending index for k-points in single pool 
  integer :: ikStart_pool
    !! Starting index for k-points in single pool 
  integer :: ios
    !! Error for input/output
  integer :: indexInPool
    !! Process index within pool
  integer :: intraPoolComm = 0
    !! Intra-pool communicator
  integer :: myid
    !! ID of this process
  integer :: myPoolId
    !! Pool index for this process
  integer :: nkPerPool
    !! Number of k-points in each pool
  integer :: nPools = 1
    !! Number of pools for k-point parallelization
  integer :: nProcs
    !! Number of processes
  integer :: nProcPerPool
    !! Number of processes per pool
  integer :: worldComm
    !! World communicator

  logical :: ionode
    !! If this node is the root node


  ! Variables that should be passed as arguments:
  real(kind=dp) :: realLattVec(3,3)
    !! Real space lattice vectors
  real(kind=dp) :: recipLattVec(3,3)
    !! Reciprocal lattice vectors
  real(kind=dp) :: eFermi
    !! Fermi energy
  real(kind=dp), allocatable :: gVecInCart(:,:)
    !! G-vectors in Cartesian coordinates
  real(kind=dp), allocatable :: bandOccupation(:,:,:)
    !! Occupation of band
  real(kind=dp) :: omega
    !! Volume of unit cell
  real(kind=dp), allocatable :: atomPositionsDir(:,:)
    !! Atom positions in direct coordinates
  real(kind=dp) :: tStart
    !! Start time
  real(kind=dp) :: wfcVecCut
    !! Energy cutoff converted to vector cutoff
  real(kind=dp), allocatable :: kPosition(:,:)
    !! Position of k-points in reciprocal space
  real(kind=dp), allocatable :: kWeight(:)
    !! Weight of k-points

  complex*16, allocatable :: eigenE(:,:,:)
    !! Band eigenvalues
  
  integer :: fftGridSize(3)
    !! Number of points on the FFT grid in each direction
  integer, allocatable :: gIndexLocalToGlobal(:)
    !! Converts local index `ig` to global index
  integer, allocatable :: gKIndexLocalToGlobal(:,:)
    !! Local to global indices for \(G+k\) vectors 
    !! ordered by magnitude at a given k-point
  integer, allocatable :: gToGkIndexMap(:,:)
    !! Index map from \(G\) to \(G+k\);
    !! indexed up to `nGVecsLocal` which
    !! is greater than `maxNumPWsPool` and
    !! stored for each k-point
  integer, allocatable :: gKIndexGlobal(:,:)
    !! Indices of \(G+k\) vectors for each k-point
    !! and all processors
  integer, allocatable :: gKIndexOrigOrderLocal(:,:)
    !! Indices of \(G+k\) vectors in just this pool
    !! and for local PWs in the original order
  integer, allocatable :: gKSort(:,:)
    !! Indices to recover sorted order on reduced
    !! \(G+k\) grid
  integer, allocatable :: iMill(:)
    !! Indices of miller indices after sorting
  integer, allocatable :: iType(:)
    !! Atom type index
  integer, allocatable :: gVecMillerIndicesGlobal(:,:)
    !! Integer coefficients for G-vectors on all processors
  integer :: nAtoms
    !! Number of atoms
  integer :: nBands
    !! Total number of bands
  integer, allocatable :: nGkLessECutGlobal(:)
    !! Global number of \(G+k\) vectors with magnitude
    !! less than `wfcVecCut` for each k-point
  integer, allocatable :: nGkLessECutLocal(:)
    !! Number of \(G+k\) vectors with magnitude
    !! less than `wfcVecCut` for each
    !! k-point, on this processor
  integer, allocatable :: nGkVecsLocal(:)
    !! Local number of G-vectors on this processor
  integer :: nGVecsGlobal
    !! Global number of G-vectors
  integer :: nGVecsLocal
    !! Local number of G-vectors on this processor
  integer :: nKPoints
    !! Total number of k-points
  integer, allocatable :: nAtomsEachType(:)
    !! Number of atoms of each type
  integer, allocatable :: nPWs1kGlobal(:)
    !! Input number of plane waves for a single k-point for all processors
  integer :: maxGIndexGlobal
    !! Maximum G-vector index among all \(G+k\)
    !! and processors
  integer :: maxGkVecsLocal
    !! Max number of G+k vectors across all k-points
    !! in this pool
  integer :: maxNumPWsGlobal
    !! Max number of \(G+k\) vectors with magnitude
    !! less than `wfcVecCut` among all k-points
  integer :: maxNumPWsPool
    !! Maximum number of \(G+k\) vectors
    !! across all k-points for just this
    !! ppool
  integer :: nAtomTypes
    !! Number of types of atoms
  integer :: nRecords
    !! Number of records in WAVECAR file
  integer :: nSpins
    !! Number of spins

  logical :: gammaOnly
    !! If the gamma only VASP code is used
  
  character(len=256) :: exportDir
    !! Directory to be used for export
  character(len=256) :: mainOutputFile
    !! Main output file
  character(len=256) :: VASPDir
    !! Directory with VASP files

  type potcar
    integer :: angMom(16) = 0
      !! Angular momentum of projectors
    integer :: iRAugMax
      !! Max index of augmentation sphere
    integer :: lmmax
      !! Total number of nlm channels
    integer :: nChannels
      !! Number of l channels;
      !! also number of projectors
    integer :: nmax
      !! Number of radial grid points

    real(kind=dp), allocatable :: dRadGrid(:)
      !! Derivative of radial grid
    real(kind=dp) :: maxGkNonlPs
      !! Max \(|G+k|\) for non-local potential
    real(kind=dp) :: psRMax
      !! Max r for non-local contribution
    real(kind=dp), allocatable :: radGrid(:)
      !! Radial grid points
    real(kind=dp) :: rAugMax
      !! Maximum radius of augmentation sphere
    real(kind=dp) :: recipProj(16,nonlPseudoGridSize)
      !! Reciprocal-space projectors
    real(kind=dp), allocatable :: wae(:,:)
      !! AE wavefunction
    real(kind=dp), allocatable :: wps(:,:)
      !! PS wavefunction

    character(len=2) :: element
  end type potcar

  type (potcar), allocatable :: pot(:)

  namelist /inputParams/ VASPDir, exportDir, gammaOnly


  contains

!----------------------------------------------------------------------------
  subroutine mpiInitialization()
    !! Generate MPI processes and communicators 
    !!
    !! <h2>Walkthrough</h2>
    !!

    implicit none

    ! Output variables:
    !logical, intent(out) :: ionode
      ! If this node is the root node
    !integer, intent(out) :: intraPoolComm = 0
      ! Intra-pool communicator
    !integer, intent(out) :: indexInPool
      ! Process index within pool
    !integer, intent(out) :: myid
      ! ID of this process
    !integer, intent(out) :: myPoolId
      ! Pool index for this process
    !integer, intent(out) :: nPools
      ! Number of pools for k-point parallelization
    !integer, intent(out) :: nProcs
      ! Number of processes
    !integer, intent(out) :: nProcPerPool
      ! Number of processes per pool
    !integer, intent(out) :: worldComm
      ! World communicator


    call MPI_Init(ierr)
    if (ierr /= 0) call mpiExitError( 8001 )

    worldComm = MPI_COMM_WORLD

    call MPI_COMM_RANK(worldComm, myid, ierr)
    if (ierr /= 0) call mpiExitError( 8002 )
      !! * Determine the rank or ID of the calling process
    call MPI_COMM_SIZE(worldComm, nProcs, ierr)
    if (ierr /= 0) call mpiExitError( 8003 )
      !! * Determine the size of the MPI pool (i.e., the number of processes)

    ionode = (myid == root)
      ! Set a boolean for if this is the root process

    call getCommandLineArguments()
      !! * Get the number of pools from the command line

    call setUpPools()
      !! * Split up processors between pools and generate MPI
      !!   communicators for pools

    return
  end subroutine mpiInitialization

!----------------------------------------------------------------------------
  subroutine getCommandLineArguments()
    !! Get the command line arguments. This currently
    !! only processes the number of pools
    !!
    !! <h2>Walkthrough</h2>
    !!

    implicit none

    ! Output variables:
    !integer, intent(out) :: nPools
      ! Number of pools for k-point parallelization


    ! Local variables:
    integer :: narg = 0
      !! Arguments processed
    integer :: nargs
      !! Total number of command line arguments
    integer :: nPools_ = 1
      !! Number of k point pools for parallelization

    character(len=256) :: arg = ' '
      !! Command line argument
    character(len=256) :: command_line = ' '
      !! Command line arguments that were not processed


    nargs = command_argument_count()
      !! * Get the number of arguments input at command line

    call MPI_BCAST(nargs, 1, MPI_INTEGER, root, worldComm, ierr)

    if(ionode) then

      call get_command_argument(narg, arg)
        !! Ignore executable
      narg = narg + 1

      do while (narg <= nargs)
        call get_command_argument(narg, arg)
          !! * Get the flag
          !! @note
          !!  This program only currently processes the number of pools,
          !!  represented by `-nk`/`-nPools`/`-nPoolss`. All other flags 
          !!  will be ignored.
          !! @endnote

        narg = narg + 1

        !> * Process the flag and store the following value
        select case (trim(arg))
          case('-nk', '-nPools', '-nPoolss') 
            call get_command_argument(narg, arg)
            read(arg, *) nPools_
            narg = narg + 1
          case default
            command_line = trim(command_line) // ' ' // trim(arg)
        end select
      enddo

      !> Write out unprocessed command line arguments, if there are any
      if(len_trim(command_line) /= 0) then
        write(*,*) 'Unprocessed command line arguments: ' // trim(command_line)
      endif

    endif

    call MPI_BCAST(nPools_, 1, MPI_INTEGER, root, worldComm, ierr)
    if(ierr /= 0) call mpiExitError(8005)

    nPools = nPools_

    return
  end subroutine getCommandLineArguments

!----------------------------------------------------------------------------
  subroutine setUpPools()
    !! Split up processors between pools and generate MPI
    !! communicators for pools
    !!
    !! <h2>Walkthrough</h2>
    !!

    implicit none

    ! Input variables:
    !integer, intent(in) :: myid
      ! ID of this process
    !integer, intent(in) :: nPools
      ! Number of pools for k-point parallelization
    !integer, intent(in) :: nProcs
      ! Number of processes


    ! Output variables:
    !integer, intent(out) :: intraPoolComm = 0
      ! Intra-pool communicator
    !integer, intent(out) :: indexInPool
      ! Process index within pool
    !integer, intent(out) :: myPoolId
      ! Pool index for this process
    !integer, intent(out) :: nProcPerPool
      ! Number of processes per pool


    if(nPools < 1 .or. nPools > nProcs) call exitError('mpiInitialization', &
      'invalid number of pools, out of range', 1)
      !! * Verify that the number of pools is between 1 and the number of processes

    if(mod(nProcs, nPools) /= 0) call exitError('mpiInitialization', &
      'invalid number of pools, mod(nProcs,nPools) /=0 ', 1)
      !! * Verify that the number of processes is evenly divisible by the number of pools

    nProcPerPool = nProcs / nPools
      !! * Calculate how many processes there are per pool

    myPoolId = myid / nProcPerPool
      !! * Get the pool index for this process

    indexInPool = mod(myid, nProcPerPool)
      !! * Get the index of the process within the pool

    call MPI_BARRIER(worldComm, ierr)
    if(ierr /= 0) call mpiExitError(8007)

    call MPI_COMM_SPLIT(worldComm, myPoolId, myid, intraPoolComm, ierr)
    if(ierr /= 0) call mpiExitError(8008)
      !! * Create intra-pool communicator

    return
  end subroutine setUpPools

!----------------------------------------------------------------------------
  subroutine initialize(gammaOnly, exportDir, VASPDir)
    !! Set the default values for input variables, open output files,
    !! and start timer
    !!
    !! <h2>Walkthrough</h2>
    !!
    
    implicit none

    ! Input variables:
    !integer, intent(in) :: nPools
      ! Number of pools for k-point parallelization
    !integer, intent(in) :: nProcs
      ! Number of processes


    ! Output variables:
    logical, intent(out) :: gammaOnly
      !! If the gamma only VASP code is used

    character(len=256), intent(out) :: exportDir
      !! Directory to be used for export
    character(len=256), intent(out) :: VASPDir
      !! Directory with VASP files


    ! Local variables:
    character(len=8) :: cdate
      !! String for date
    character(len=10) :: ctime
      !! String for time

    VASPDir = './'
    exportDir = './Export'
    gammaOnly = .false.

    call cpu_time(tStart)

    call date_and_time(cdate, ctime)

    if(ionode) then

      write(iostd, '(/5X,"VASP wavefunction export program starts on ",A9," at ",A9)') &
             cdate, ctime

      write(iostd, '(/5X,"Parallel version (MPI), running on ",I5," processors")') nProcs

      if(nPools > 1) write(iostd, '(5X,"K-points division:     nPools     = ",I7)') nPools

    else

      open(unit = iostd, file='/dev/null', status='unknown')
        ! Make the iostd unit point to null for non-root processors
        ! to avoid tons of duplicate output

    endif

  end subroutine initialize

!----------------------------------------------------------------------------
  subroutine mpiSumIntV(msg, comm)
    !! Perform `MPI_ALLREDUCE` sum for an integer vector
    !! using a max buffer size
    !!
    !! <h2>Walkthrough</h2>
    !!

    implicit none

    ! Input/output variables:
    integer, intent(in) :: comm
      !! MPI communicator
    integer, intent(inout) :: msg(:)
      !! Message to be sent


    ! Local variables:
    integer, parameter :: maxb = 100000
      !! Max buffer size

    integer :: ib
      !! Loop index
    integer :: buff(maxb)
      !! Buffer
    integer :: msglen
      !! Length of message to be sent
    integer :: nbuf
      !! Number of buffers

    msglen = size(msg)

    nbuf = msglen/maxb
      !! * Get the number of buffers of size `maxb` needed
  
    do ib = 1, nbuf
      !! * Send message in buffers of size `maxb`
     
        call MPI_ALLREDUCE(msg(1+(ib-1)*maxb), buff, maxb, MPI_INTEGER, MPI_SUM, comm, ierr)
        if(ierr /= 0) call exitError('mpiSumIntV', 'error in mpi_allreduce 1', ierr)

        msg((1+(ib-1)*maxb):(ib*maxb)) = buff(1:maxb)

    enddo

    if((msglen - nbuf*maxb) > 0 ) then
      !! * Send any data left of size less than `maxb`

        call MPI_ALLREDUCE(msg(1+nbuf*maxb), buff, (msglen-nbuf*maxb), MPI_INTEGER, MPI_SUM, comm, ierr)
        if(ierr /= 0) call exitError('mpiSumIntV', 'error in mpi_allreduce 2', ierr)

        msg((1+nbuf*maxb):msglen) = buff(1:(msglen-nbuf*maxb))
    endif

    return
  end subroutine mpiSumIntV

!----------------------------------------------------------------------------
  subroutine mpiSumDoubleV(msg, comm)
    !! Perform `MPI_ALLREDUCE` sum for a double-precision vector
    !! using a max buffer size
    !!
    !! <h2>Walkthrough</h2>
    !!

    implicit none

    ! Input/output variables:
    integer, intent(in) :: comm
      !! MPI communicator

    real(kind=dp), intent(inout) :: msg(:)
      !! Message to be sent


    ! Local variables:
    integer, parameter :: maxb = 20000
      !! Max buffer size

    integer :: ib
      !! Loop index
    integer :: msglen
      !! Length of message to be sent
    integer :: nbuf
      !! Number of buffers

    real(kind=dp) :: buff(maxb)
      !! Buffer

    msglen = size(msg)

    nbuf = msglen/maxb
      !! * Get the number of buffers of size `maxb` needed

    do ib = 1, nbuf
      !! * Send message in buffers of size `maxb`
     
        call MPI_ALLREDUCE(msg(1+(ib-1)*maxb), buff, maxb, MPI_DOUBLE_PRECISION, MPI_SUM, comm, ierr)
        if(ierr /= 0) call exitError('mpiSumDoubleV', 'error in mpi_allreduce 1', ierr)

        msg((1+(ib-1)*maxb):(ib*maxb)) = buff(1:maxb)

    enddo

    if((msglen - nbuf*maxb) > 0 ) then
      !! * Send any data left of size less than `maxb`

        call MPI_ALLREDUCE(msg(1+nbuf*maxb), buff, (msglen-nbuf*maxb), MPI_DOUBLE_PRECISION, MPI_SUM, comm, ierr)
        if(ierr /= 0) call exitError('mpiSumDoubleV', 'error in mpi_allreduce 2', ierr)

        msg((1+nbuf*maxb):msglen) = buff(1:(msglen-nbuf*maxb))
    endif

    return
  end subroutine mpiSumDoubleV

!----------------------------------------------------------------------------
  subroutine mpiSumComplexV(msg, comm)
    !! Perform `MPI_ALLREDUCE` sum for a complex vector
    !! using a max buffer size
    !!
    !! <h2>Walkthrough</h2>
    !!

    implicit none

    ! Input/output variables:
    integer, intent(in) :: comm
      !! MPI communicator

    complex(kind=dp), intent(inout) :: msg(:)
      !! Message to be sent


    ! Local variables:
    integer, parameter :: maxb = 10000
      !! Max buffer size

    integer :: ib
      !! Loop index
    integer :: msglen
      !! Length of message to be sent
    integer :: nbuf
      !! Number of buffers
    integer :: commSize

    complex(kind=dp) :: buff(maxb)
      !! Buffer


    msglen = size(msg)

    nbuf = msglen/maxb
      !! * Get the number of buffers of size `maxb` needed
  
    do ib = 1, nbuf
      !! * Send message in buffers of size `maxb`
     
        call MPI_ALLREDUCE(msg(1+(ib-1)*maxb), buff, maxb, MPI_DOUBLE_COMPLEX, MPI_SUM, comm, ierr)
        if(ierr /= 0) call exitError('mpiSumComplexV', 'error in mpi_allreduce 1', ierr)

        msg((1+(ib-1)*maxb):(ib*maxb)) = buff(1:maxb)

    enddo

    if((msglen - nbuf*maxb) > 0 ) then
      !! * Send any data left of size less than `maxb`

        call MPI_ALLREDUCE(msg(1+nbuf*maxb), buff, (msglen-nbuf*maxb), MPI_DOUBLE_COMPLEX, MPI_SUM, comm, ierr)
        if(ierr /= 0) call exitError('mpiSumComplexV', 'error in mpi_allreduce 2', ierr)

        msg((1+nbuf*maxb):msglen) = buff(1:(msglen-nbuf*maxb))
    endif

    return
  end subroutine mpiSumComplexV

!----------------------------------------------------------------------------
  subroutine mpiExitError(code)
    !! Exit on error with MPI communication

    implicit none
    
    integer, intent(in) :: code

    write( iostd, '( "*** MPI error ***")' )
    write( iostd, '( "*** error code: ",I5, " ***")' ) code

    call MPI_ABORT(worldComm,code,ierr)
    
    stop

    return
  end subroutine mpiExitError

!----------------------------------------------------------------------------
  subroutine exitError(calledFrom, message, ierror)
    !! Output error message and abort if ierr > 0
    !!
    !! Can ensure that error will cause abort by
    !! passing abs(ierror)
    !!
    !! <h2>Walkthrough</h2>
    !!
    
    implicit none

    integer, intent(in) :: ierror
      !! Error

    character(len=*), intent(in) :: calledFrom
      !! Place where this subroutine was called from
    character(len=*), intent(in) :: message
      !! Error message

    integer :: id
      !! ID of this process
    integer :: mpierr
      !! Error output from MPI

    character(len=6) :: cerr
      !! String version of error


    if ( ierror <= 0 ) return
      !! * Do nothing if the error is less than or equal to zero

    write( cerr, fmt = '(I6)' ) ierror
      !! * Write ierr to a string
    write(unit=*, fmt = '(/,1X,78("%"))' )
      !! * Output a dividing line
    write(unit=*, fmt = '(5X,"Error in ",A," (",A,"):")' ) trim(calledFrom), trim(adjustl(cerr))
      !! * Output where the error occurred and the error
    write(unit=*, fmt = '(5X,A)' ) TRIM(message)
      !! * Output the error message
    write(unit=*, fmt = '(1X,78("%"),/)' )
      !! * Output a dividing line

    write( *, '("     stopping ...")' )
  
    call flush( iostd )
  
    id = 0
  
    !> * For MPI, get the id of this process and abort
    call MPI_COMM_RANK( worldComm, id, mpierr )
    call MPI_ABORT( worldComm, mpierr, ierr )
    call MPI_FINALIZE( mpierr )

    stop 2

    return

  end subroutine exitError

!----------------------------------------------------------------------------
  subroutine readWAVECAR(VASPDir, realLattVec, recipLattVec, bandOccupation, omega, wfcVecCut, &
        kPosition, nBands, nKPoints, nPWs1kGlobal, nRecords, nSpins, eigenE)
    !! Read cell and wavefunction data from the WAVECAR file
    !!
    !! <h2>Walkthrough</h2>
    !!

    implicit none

    ! Input variables:
    character(len=256), intent(in) :: VASPDir
      !! Directory with VASP files

    
    ! Output variables:
    real(kind=dp), intent(out) :: realLattVec(3,3)
      !! Real space lattice vectors
    real(kind=dp), intent(out) :: recipLattVec(3,3)
      !! Reciprocal lattice vectors
    real(kind=dp), allocatable, intent(out) :: bandOccupation(:,:,:)
      !! Occupation of band
    real(kind=dp), intent(out) :: omega
      !! Volume of unit cell
    real(kind=dp), intent(out) :: wfcVecCut
      !! Energy cutoff converted to vector cutoff
    real(kind=dp), allocatable, intent(out) :: kPosition(:,:)
      !! Position of k-points in reciprocal space

    integer, intent(out) :: nBands
      !! Total number of bands
    integer, intent(out) :: nKPoints
      !! Total number of k-points
    integer, allocatable, intent(out) :: nPWs1kGlobal(:)
      !! Input number of plane waves for a single k-point 
      !! for all processors
    integer, intent(out) :: nRecords
      !! Number of records in WAVECAR file
    integer, intent(out) :: nSpins
      !! Number of spins

    complex*16, allocatable, intent(out) :: eigenE(:,:,:)
      !! Band eigenvalues


    ! Local variables:
    real(kind=dp) :: c = 0.26246582250210965422
      !! \(2m/\hbar^2\) converted from J\(^{-1}\)m\(^{-2}\)
      !! to eV\(^{-1}\)A\(^{-2}\)
    real(kind=dp) :: nRecords_real, nspin_real, prec_real, nkstot_real 
      !! Real version of integers for reading from file
    real(kind=dp) :: nbnd_real
      !! Real version of integers for reading from file
    real(kind=dp) :: wfcECut
      !! Plane wave energy cutoff in Ry

    integer :: j
      !! Index used for reading lattice vectors
    integer :: prec
      !! Precision of plane wave coefficients

    character(len=256) :: fileName
      !! Full WAVECAR file name including path

    
    if(ionode) then

      fileName = trim(VASPDir)//'/WAVECAR'

      nRecords = 24
        ! Set a starting value for the number of records

      open(unit=wavecarUnit, file=fileName, access='direct', recl=nRecords, iostat=ierr, status='old')
      if (ierr .ne. 0) write(iostd,*) 'open error - iostat =', ierr
        !! * If root node, open the `WAVECAR` file

      read(unit=wavecarUnit,rec=1) nRecords_real, nspin_real, prec_real
        !! @note Must read in as real first then convert to integer @endnote

      close(unit=wavecarUnit)

      nRecords = nint(nRecords_real)
      nSpins = nint(nspin_real)
      prec = nint(prec_real)
        ! Convert input variables to integers

      if(prec .eq. 45210) call exitError('readWAVECAR', 'WAVECAR_double requires complex*16', 1)

      open(unit=wavecarUnit, file=fileName, access='direct', recl=nRecords, iostat=ierr, status='old')
      if (ierr .ne. 0) write(iostd,*) 'open error - iostat =', ierr
        !! * Reopen WAVECAR with correct number of records

      read(unit=wavecarUnit,rec=2) nkstot_real, nbnd_real, wfcECut,(realLattVec(j,1),j=1,3),&
          (realLattVec(j,2),j=1,3), (realLattVec(j,3),j=1,3)
        !! * Read total number of k-points, plane wave cutoff energy, and real
        !!   space lattice vectors
      !read(unit=wavecarUnit,rec=2) nkstot_real, nbnd_real, wfcECut,((realLattVec(i,j),j=1,3),i=1,3)
        !! @todo Test this more compact form @endtodo

      close(wavecarUnit)

      wfcVecCut = sqrt(wfcECut*c)/angToBohr
        !! * Calculate vector cutoff from energy cutoff

      realLattVec = realLattVec*angToBohr

      nKPoints = nint(nkstot_real)
      nBands = nint(nbnd_real)
        ! Convert input variables to integers

      call calculateOmega(realLattVec, omega)
        !! * Calculate the cell volume as \(a_1\cdot a_2\times a_3\)

      call getReciprocalVectors(realLattVec, omega, recipLattVec)
        !! * Calculate the reciprocal lattice vectors from the real-space
        !!   lattice vectors and the cell volume

      !> * Write out total number of k-points, number of bands, 
      !>   the energy cutoff, the real-space-lattice vectors,
      !>   the cell volume, and the reciprocal lattice vectors
      write(iostd,*) 'no. k points =', nKPoints
      write(iostd,*) 'no. bands =', nBands
      write(iostd,*) 'max. energy (eV) =', sngl(wfcECut)
        !! @note 
        !!  The energy cutoff is currently output to the `iostd` file
        !!  in eV to compare with output from WaveTrans.
        !! @endnote
      write(iostd,*) 'real space lattice vectors:'
      write(iostd,*) 'a1 =', (sngl(realLattVec(j,1)),j=1,3)
      write(iostd,*) 'a2 =', (sngl(realLattVec(j,2)),j=1,3)
      write(iostd,*) 'a3 =', (sngl(realLattVec(j,3)),j=1,3)
      write(iostd,*) 
      write(iostd,*) 'volume unit cell =', sngl(omega)
      write(iostd,*) 
      write(iostd,*) 'reciprocal lattice vectors:'
      write(iostd,*) 'b1 =', (sngl(recipLattVec(j,1)),j=1,3)
      write(iostd,*) 'b2 =', (sngl(recipLattVec(j,2)),j=1,3)
      write(iostd,*) 'b3 =', (sngl(recipLattVec(j,3)),j=1,3)
      write(iostd,*) 
        !! @note
        !!  I made an intentional choice to stick with the unscaled lattice
        !!  vectors until I see if it will be convenient to scale them down.
        !!  QE uses the `alat` and `tpiba` scaling quite a bit though, so I
        !!  will have to be careful with the scaling/units.
        !! @endnote

      write(mainOutFileUnit, '("# Cell volume (a.u.)^3. Format: ''(ES24.15E3)''")')
      write(mainOutFileUnit, '(ES24.15E3)' ) omega
      flush(mainOutFileUnit)

    endif

    call MPI_BCAST(nRecords, 1, MPI_INTEGER, root, worldComm, ierr)
    call MPI_BCAST(nSpins, 1, MPI_INTEGER, root, worldComm, ierr)
    call MPI_BCAST(nKPoints, 1, MPI_INTEGER, root, worldComm, ierr)
    call MPI_BCAST(nBands, 1, MPI_INTEGER, root, worldComm, ierr)
    call MPI_BCAST(wfcVecCut, 1, MPI_DOUBLE_PRECISION, root, worldComm, ierr)
    call MPI_BCAST(omega, 1, MPI_DOUBLE_PRECISION, root, worldComm, ierr)
    call MPI_BCAST(realLattVec, size(realLattVec), MPI_DOUBLE_PRECISION, root, worldComm, ierr)
    call MPI_BCAST(recipLattVec, size(recipLattVec), MPI_DOUBLE_PRECISION, root, worldComm, ierr)

    call preliminaryWAVECARScan(nBands, nKPoints, nRecords, nSpins, bandOccupation, kPosition, nPWs1kGlobal, eigenE)
      !! * For each spin and k-point, read the number of
      !!   \(G+k\) vectors below the energy cutoff, the
      !!   position of the k-point in reciprocal space, 
      !!   and the eigenvalue and occupation for each band

    return
  end subroutine readWAVECAR

!----------------------------------------------------------------------------
  subroutine calculateOmega(realLattVec, omega)
    !! Calculate the cell volume as \(a_1\cdot a_2\times a_3\)

    implicit none

    ! Input variables:
    real(kind=dp), intent(in) :: realLattVec(3,3)
      !! Real space lattice vectors


    ! Output variables:
    real(kind=dp), intent(out) :: omega
      !! Volume of unit cell


    ! Local variables:
    real(kind=dp) :: vtmp(3)
      !! \(a_2\times a_3\)


    call vcross(realLattVec(:,2), realLattVec(:,3), vtmp)

    omega = sum(realLattVec(:,1)*vtmp(:))

    return
  end subroutine calculateOmega

!----------------------------------------------------------------------------
  subroutine getReciprocalVectors(realLattVec, omega, recipLattVec)
    !! Calculate the reciprocal lattice vectors from the real-space
    !! lattice vectors and the cell volume

    implicit none

    ! Input variables:
    real(kind=dp), intent(in) :: realLattVec(3,3)
      !! Real space lattice vectors
    real(kind=dp), intent(in) :: omega
      !! Volume of unit cell


    ! Output variables:
    real(kind=dp), intent(out) :: recipLattVec(3,3)
      !! Reciprocal lattice vectors


    ! Local variables:
    integer :: i
      !! Loop index
    

    call vcross(2.0d0*pi*realLattVec(:,2)/omega, realLattVec(:,3), recipLattVec(:,1))
      ! \(b_1 = 2\pi/\Omega a_2\times a_3\)
    call vcross(2.0d0*pi*realLattVec(:,3)/omega, realLattVec(:,1), recipLattVec(:,2))
      ! \(b_2 = 2\pi/\Omega a_3\times a_1\)
    call vcross(2.0d0*pi*realLattVec(:,1)/omega, realLattVec(:,2), recipLattVec(:,3))
      ! \(b_3 = 2\pi/\Omega a_1\times a_2\)


    return
  end subroutine getReciprocalVectors

!----------------------------------------------------------------------------
  subroutine vcross(vec1, vec2, crossProd)
    !! Calculate the cross product `crossProd` of 
    !! two vectors `vec1` and `vec2`

    implicit none

    ! Input variables:
    real(kind=dp), intent(in) :: vec1(3), vec2(3)
      !! Input vectors


    ! Output variables:
    real(kind=dp), intent(out) :: crossProd(3)
      !! Cross product of input vectors


    crossProd(1) = vec1(2)*vec2(3) - vec1(3)*vec2(2)
    crossProd(2) = vec1(3)*vec2(1) - vec1(1)*vec2(3)
    crossProd(3) = vec1(1)*vec2(2) - vec1(2)*vec2(1)

    return
  end subroutine vcross

!----------------------------------------------------------------------------
  subroutine preliminaryWAVECARScan(nBands, nKPoints, nRecords, nSpins, bandOccupation, kPosition, nPWs1kGlobal, eigenE)
    !! For each spin and k-point, read the number of
    !! \(G+k\) vectors below the energy cutoff, the
    !! position of the k-point in reciprocal space, 
    !! and the eigenvalue and occupation for each band
    !!
    !! <h2>Walkthrough</h2>
    !!

    implicit none

    ! Input variables:
    integer, intent(in) :: nBands
      !! Total number of bands
    integer, intent(in) :: nKPoints
      !! Total number of k-points
    integer, intent(in) :: nRecords
      !! Number of records in the WAVECAR file
    integer, intent(in) :: nSpins
      !! Number of spins


    ! Output variables:
    real(kind=dp), allocatable, intent(out) :: bandOccupation(:,:,:)
      !! Occupation of band
    real(kind=dp), allocatable, intent(out) :: kPosition(:,:)
      !! Position of k-points in reciprocal space

    integer, allocatable, intent(out) :: nPWs1kGlobal(:)
      !! Input number of plane waves for a single k-point 
      !! for all processors

    complex*16, allocatable, intent(out) :: eigenE(:,:,:)
      !! Band eigenvalues


    ! Local variables:
    real(kind=dp) :: nPWs1kGlobal_real
      !! Real version of integers for reading from file

    integer :: irec, isp, ik, i, iband, iplane
      !! Loop indices

    character(len=256) :: fileName
      !! Full WAVECAR file name including path


    allocate(bandOccupation(nSpins, nBands, nKPoints))
    allocate(kPosition(3,nKPoints))
    allocate(nPWs1kGlobal(nKPoints))
    allocate(eigenE(nSpins,nKPoints,nBands))
    
    fileName = trim(VASPDir)//'/WAVECAR'

    if(ionode) then
      open(unit=wavecarUnit, file=fileName, access='direct', recl=nRecords, iostat=ierr, status='old')
      if (ierr .ne. 0) write(iostd,*) 'open error - iostat =', ierr

      irec=2

      write(iostd,*) 'Completing preliminary scan of WAVECAR'

      do isp = 1, nSpins
        !! * For each spin:
        !!    * Go through each k-point
        !!       * Read in the number of \(G+k\) plane wave
        !!         vectors below the energy cutoff
        !!       * Read the position of the k-point in 
        !!         reciprocal space
        !!       * Read in the eigenvalue and occupation for
        !!         each band

        write(iostd,*) '  Reading spin ', isp

        do ik = 1, nKPoints
        
          irec = irec + 1

          read(unit=wavecarUnit,rec=irec) nPWs1kGlobal_real, (kPosition(i,ik),i=1,3), &
                 (eigenE(isp,ik,iband), bandOccupation(isp, iband, ik), iband=1,nBands)
            ! Read in the number of \(G+k\) plane wave vectors below the energy
            ! cutoff, the position of the k-point in reciprocal space, and
            ! the eigenvalue and occupation for each band

          nPWs1kGlobal(ik) = nint(nPWs1kGlobal_real)
            !! @note
            !!  `nPWs1kGlobal(ik)` corresponds to `WDES%NPLWKP_TOT(K)` in VASP (see 
            !!  subroutine `OUTWAV` in `fileio.F`). In the `GEN_INDEX` subroutine in
            !!  `wave.F`, `WDES%NGVECTOR(NK) = WDES%NPLWKP(NK)/WDES%NRSPINORS`, where
            !!  `NRSPINORS=1` for our case. `WDES%NPLWKP(NK)` and `WDES%NPLWKP_TOT(K)`
            !!  are set the same way and neither `NGVECTOR(NK)` nor `NPLWKP_TOT(K)` are
            !!  changed anywhere else, so I am treating them as equivalent. I am not
            !!  sure why there are two separate variables defined.
            !! @endnote

          irec = irec + nBands
            ! Skip the records for the plane-wave coefficients for now.
            ! Those are read in the `readAndWriteWavefunction` subroutine.

        enddo
      enddo

      close(wavecarUnit)

      eigenE(:,:,:) = eigenE(:,:,:)*eVToRy

    endif

    call MPI_BCAST(kPosition, size(kPosition), MPI_DOUBLE_PRECISION, root, worldComm, ierr)
    call MPI_BCAST(bandOccupation, size(bandOccupation), MPI_DOUBLE_PRECISION, root, worldComm, ierr)
    call MPI_BCAST(eigenE, size(eigenE), MPI_COMPLEX, root, worldComm, ierr)
    call MPI_BCAST(nPWs1kGlobal, size(nPWs1kGlobal), MPI_INTEGER, root, worldComm, ierr)

    if(ionode) write(iostd,*) 'Preliminary scan complete.'

    return

  end subroutine preliminaryWAVECARScan


!----------------------------------------------------------------------------
  subroutine distributeKpointsInPools(nKPoints)
    !! Figure out how many k-points there should be per pool
    !!
    !! <h2>Walkthrough</h2>
    !!

    implicit none

    ! Input variables:
    integer, intent(in) :: nKPoints
      !! Total number of k-points
    !integer, intent(in) :: nProcPerPool
      ! Number of processes per pool


    ! Output variables:
    !integer, intent(out) :: ikEnd_pool
      ! Ending index for k-points in single pool 
    !integer, intent(out) :: ikStart_pool
      ! Starting index for k-points in single pool 
    !integer, intent(out) :: nkPerPool
      ! Number of k-points in each pool


    ! Local variables:
    integer :: nkr
      !! Number of k-points left over after evenly divided across pools


    if( nKPoints > 0 ) then

      IF( ( nProcPerPool > nProcs ) .or. ( mod( nProcs, nProcPerPool ) /= 0 ) ) &
        CALL exitError( 'distributeKpointsInPools','nProcPerPool', 1 )

      nkPerPool = nKPoints / nPools
        !!  * Calculate k-points per pool

      nkr = nKPoints - nkPerPool * nPools 
        !! * Calculate the remainder `nkr`

      IF( myPoolId < nkr ) nkPerPool = nkPerPool + 1
        !! * Assign the remainder to the first `nkr` pools

      !>  * Calculate the index of the first k-point in this pool
      ikStart_pool = nkPerPool * myPoolId + 1
      IF( myPoolId >= nkr ) ikStart_pool = ikStart_pool + nkr

      ikEnd_pool = ikStart_pool + nkPerPool - 1
        !!  * Calculate the index of the last k-point in this pool

    endif

    return
  end subroutine distributeKpointsInPools

!----------------------------------------------------------------------------
  subroutine read_vasprun_xml(realLattVec, nKPoints, VASPDir, atomPositionsDir, eFermi, kWeight, fftGridSize, iType, nAtoms, nAtomsEachType, nAtomTypes)
    !! Read the k-point weights and cell info from the `vasprun.xml` file
    !!
    !! <h2>Walkthrough</h2>
    !!

    implicit none

    ! Input variables:
    real(kind=dp), intent(in) :: realLattVec(3,3)
      !! Real space lattice vectors

    integer, intent(in) :: nKPoints
      !! Total number of k-points

    character(len=256), intent(in) :: VASPDir
      !! Directory with VASP files


    ! Output variables:
    real(kind=dp), allocatable, intent(out) :: atomPositionsDir(:,:)
      !! Atom positions in direct coordinates
    real(kind=dp), intent(out) :: eFermi
      !! Fermi energy
    real(kind=dp), allocatable, intent(out) :: kWeight(:)
      !! K-point weights

    integer, intent(out) :: fftGridSize(3)
      !! Number of points on the FFT grid in each direction
    integer, allocatable, intent(out) :: iType(:)
      !! Atom type index
    integer, intent(out) :: nAtoms
      !! Number of atoms
    integer, allocatable, intent(out) :: nAtomsEachType(:)
      !! Number of atoms of each type
    integer, intent(out) :: nAtomTypes
      !! Number of types of atoms


    ! Local variables:
    integer :: ik, ia, ix, i
      !! Loop indices

    character(len=256) :: cDum
      !! Dummy variable to ignore input
    character(len=256) :: fileName
      !! `vasprun.xml` with path
    character(len=256) :: line
      !! Line read from file

    logical :: fileExists
      !! If the `vasprun.xml` file exists
    logical :: found
      !! If the required tag was found
    logical :: orbitalMag
      !! If can safely ignore `VKPT_SHIFT`
    logical :: spinSpiral
      !! If spin spirals considered (LSPIRAL)
    logical :: useRealProj
      !! If real-space projectors are used (LREAL)

    allocate(kWeight(nKPoints))

    if (ionode) then

      fileName = trim(VASPDir)//'/vasprun.xml'

      inquire(file = fileName, exist = fileExists)

      if (.not. fileExists) call exitError('read_vasprun_xml', 'Required file vasprun.xml does not exist', 1)

      open(57, file=fileName)
        !! * If root node, open `vasprun.xml`


      found = .false.
      do while (.not. found)
        !! * Ignore everything until you get to a
        !!   line with `'weights'`, indicating the
        !!   tag surrounding the k-point weights
        
        read(57, '(A)') line

        if (index(line,'weights') /= 0) found = .true.
        
      enddo

      do ik = 1, nKPoints
        !! * Read in the weight for each k-point

        read(57,*) cDum, kWeight(ik), cDum

      enddo


      found = .false.
      do while (.not. found)
        !! * Ignore everything until you get to a
        !!   line with `'LREAL'`, indicating the
        !!   tag that determines if real-space 
        !!   projectors are used
        
        read(57, '(A)') line

        if (index(line,'LREAL') /= 0) found = .true.
        
      enddo

      read(line,'(a35,L4,a4)') cDum, useRealProj, cDum

      if(useRealProj) call exitError('read_vasprun_xml', &
        '*** error - expected LREAL = F but got T', 1)


      found = .false.
      do while (.not. found)
        !! * Ignore everything until you get to a
        !!   line with `'LSPIRAL'`, indicating the
        !!   tag that determines if spin spirals are
        !!   included
        
        read(57, '(A)') line

        if (index(line,'LSPIRAL') /= 0) found = .true.
        
      enddo

      read(line,'(a37,L4,a4)') cDum, spinSpiral, cDum

      if(spinSpiral) call exitError('read_vasprun_xml', &
        '*** error - expected LSPIRAL = F but got T', 1)


      found = .false.
      do while (.not. found)
        !! * Ignore everything until you get to a
        !!   line with `'grids'`, indicating the
        !!   tag surrounding the k-point weights
        
        read(57, '(A)') line

        if (index(line,'grids') /= 0) found = .true.
        
      enddo

      do ix = 1, 3
        !! * Read in the FFT grid size in each direction

        read(57,'(a28,i6,a4)') cDum, fftGridSize(ix), cDum

      enddo


      found = .false.
      do while (.not. found)
        !! * Ignore everything until you get to a
        !!   line with `'ORBITALMAG'`, indicating the
        !!   tag that determines if can ignore `VKPT_SHIFT`
        
        read(57, '(A)') line

        if (index(line,'ORBITALMAG') /= 0) found = .true.
        
      enddo

      read(line,'(a39,L4,a4)') cDum, orbitalMag, cDum

      if(orbitalMag) call exitError('read_vasprun_xml', &
        '*** error - expected ORBITALMAG = F but got T', 1)


      found = .false.
      do while (.not. found)
        !! * Ignore everything until you get to a
        !!   line with `'atominfo'`, indicating the
        !!   tag surrounding the cell info
        
        read(57, '(A)') line

        if (index(line,'atominfo') /= 0) found = .true.
        
      enddo

      read(57,*) cDum, nAtoms, cDum
      read(57,*) cDum, nAtomTypes, cDum
      read(57,*) 
      read(57,*) 
      read(57,*) 
      read(57,*) 
      read(57,*) 

      allocate(iType(nAtoms), nAtomsEachType(nAtomTypes))

      nAtomsEachType = 0
      do ia = 1, nAtoms
        !! * Read in the atom type index for each atom
        !!   and calculate the number of atoms of each
        !!   type

        read(57,'(a21,i3,a9)') cDum, iType(ia), cDum

        nAtomsEachType(iType(ia)) = nAtomsEachType(iType(ia)) + 1

      enddo

      found = .false.
      do while (.not. found)
        !! * Ignore everything until you get to a
        !!   line with `'efermi'`, indicating the
        !!   tag with the Fermi energy
        
        read(57, '(A)') line

        if (index(line,'efermi') /= 0) found = .true.
        
      enddo

      read(line,*) cDum, cDum, eFermi, cDum
      eFermi = eFermi*eVToRy

      found = .false.
      do while (.not. found)
        !! * Ignore everything until you get to a
        !!   line with `'finalpos'`, indicating the
        !!   tag surrounding the final cell parameters
        !!   and positions
        
        read(57, '(A)') line

        if (index(line,'finalpos') /= 0) found = .true.
        
      enddo

      found = .false.
      do while (.not. found)
        !! * Ignore everything until you get to a
        !!   line with `'positions'`, indicating the
        !!   tag surrounding the final positions
        
        read(57, '(A)') line

        if (index(line,'positions') /= 0) found = .true.
        
      enddo

      allocate(atomPositionsDir(3,nAtoms))

      do ia = 1, nAtoms
        !! * Read in the final position for each atom

        read(57,*) cDum, (atomPositionsDir(i,ia),i=1,3), cDum
          !! @note
          !!  I assume that the coordinates are always direct
          !!  in the `vasprun.xml` file and that the scaling
          !!  factor is already included as I cannot find it 
          !!  listed anywhere in that file. Extensive testing
          !!  needs to be done to confirm this assumption.
          !! @endnote

      enddo

      if(maxval(atomPositionsDir) > 1) call exitError('read_vasprun_xml', &
        '*** error - expected direct coordinates', 1)

      close(57)

    endif

    call MPI_BCAST(kWeight, size(kWeight), MPI_DOUBLE_PRECISION, root, worldComm, ierr)
    call MPI_BCAST(fftGridSize, size(fftGridSize), MPI_INTEGER, root, worldComm, ierr)
    call MPI_BCAST(nAtoms, 1, MPI_INTEGER, root, worldComm, ierr)
    call MPI_BCAST(nAtomTypes, 1, MPI_INTEGER, root, worldComm, ierr)

    if (.not. ionode) then
      allocate(iType(nAtoms))
      allocate(atomPositionsDir(3,nAtoms))
      allocate(nAtomsEachType(nAtomTypes))
    endif

    call MPI_BCAST(iType, size(iType), MPI_INTEGER, root, worldComm, ierr)
    call MPI_BCAST(atomPositionsDir, size(atomPositionsDir), MPI_DOUBLE_PRECISION, root, worldComm, ierr)
    call MPI_BCAST(nAtomsEachType, size(nAtomsEachType), MPI_INTEGER, root, worldComm, ierr)

    return
  end subroutine read_vasprun_xml

!----------------------------------------------------------------------------
  subroutine calculateGvecs(fftGridSize, recipLattVec, gVecInCart, gIndexLocalToGlobal, gVecMillerIndicesGlobal, &
      iMill, nGVecsGlobal, nGVecsLocal)
    !! Calculate Miller indices and G-vectors and split
    !! over processors
    !!
    !! <h2>Walkthrough</h2>
    !!

    implicit none

    ! Input variables:
    integer, intent(in) :: fftGridSize(3)
      !! Number of points on the FFT grid in each direction

    real(kind=dp), intent(in) :: recipLattVec(3,3)
      !! Reciprocal lattice vectors


    ! Output variables:
    real(kind=dp), allocatable, intent(out) :: gVecInCart(:,:)
      !! G-vectors in Cartesian coordinates

    integer, allocatable, intent(out) :: gIndexLocalToGlobal(:)
      !! Converts local index `ig` to global index
    integer, allocatable, intent(out) :: gVecMillerIndicesGlobal(:,:)
      !! Integer coefficients for G-vectors on all processors
    integer, allocatable, intent(out) :: iMill(:)
      !! Indices of miller indices after sorting
    integer, intent(out) :: nGVecsGlobal
      !! Global number of G-vectors
    integer, intent(out) :: nGVecsLocal
      !! Local number of G-vectors on this processor


    ! Local variables:
    real(kind=dp) :: eps8 = 1.0E-8_dp
      !! Double precision zero
    real(kind=dp), allocatable :: millSum(:)
      !! Sum of integer coefficients for G-vectors

    integer :: igx, igy, igz, ig, ix
      !! Loop indices
    integer, allocatable :: gVecMillerIndicesGlobal_tmp(:,:)
      !! Integer coefficients for G-vectors on all processors
    integer, allocatable :: mill_local(:,:)
      !! Integer coefficients for G-vectors
    integer :: millX, millY, millZ
      !! Miller indices for each direction; in order
      !! 0,1,...,(fftGridSize(:)/2),-(fftGridSize(:)/2-1),...,-1
    integer :: npmax
      !! Max number of plane waves


    npmax = fftGridSize(1)*fftGridSize(2)*fftGridSize(3) 
    allocate(gVecMillerIndicesGlobal(3,npmax))
    allocate(millSum(npmax))

    if(ionode) then

      allocate(gVecMillerIndicesGlobal_tmp(3,npmax))

      write(iostd,*)
      write(iostd,*) "***************"
      write(iostd,*) "Calculating miller indices"

      nGVecsGlobal = 0
      gVecMillerIndicesGlobal_tmp = 0

      !> * Generate Miller indices for every possible G-vector
      !>   regardless of the \(|G+k|\) cutoff
      do igz = 1, fftGridSize(3)

        millZ = igz - 1

        if (igz - 1 .gt. fftGridSize(3)/2) millZ = igz - 1 - fftGridSize(3)

        do igy = 1, fftGridSize(2)

          millY = igy - 1

          if (igy - 1 .gt. fftGridSize(2)/2) millY = igy - 1 - fftGridSize(2)

          do igx = 1, fftGridSize(1)

            millX = igx - 1

            if (igx - 1 .gt. fftGridSize(1)/2) millX = igx - 1 - fftGridSize(1)

            nGVecsGlobal = nGVecsGlobal + 1

            gVecMillerIndicesGlobal_tmp(1,nGVecsGlobal) = millX
            gVecMillerIndicesGlobal_tmp(2,nGVecsGlobal) = millY
            gVecMillerIndicesGlobal_tmp(3,nGVecsGlobal) = millZ
              !! * Calculate Miller indices

            millSum(nGVecsGlobal) = sqrt(real(millX**2 + millY**2 + millZ**2))
              !! * Calculate the sum of the Miller indices
              !!   for sorting

          enddo
        enddo
      enddo

      if (nGVecsGlobal .ne. npmax) call exitError('calculateGvecs', & 
        '*** error - computed no. of G-vectors != estimated number of plane waves', 1)
        !! * Check that number of G-vectors are the same as the number of plane waves

      write(iostd,*) "Sorting miller indices"

      allocate(iMill(nGVecsGlobal))

      do ig = 1, nGVecsGlobal
        !! * Initialize the index array that will track elements
        !!   after sorting

        iMill(ig) = ig

      enddo

      call hpsort_eps(nGVecsGlobal, millSum, iMill, eps8)
        !! * Order indices `iMill` by the G-vector length `millSum`

      deallocate(millSum)

      do ig = 1, nGVecsGlobal
        !! * Rearrange the miller indices to match order of `millSum`

        gVecMillerIndicesGlobal(:,ig) = gVecMillerIndicesGlobal_tmp(:,iMill(ig))

      enddo

      deallocate(gVecMillerIndicesGlobal_tmp)

      write(*,*) "Done calculating and sorting miller indices"
      write(*,*) "***************"
      write(*,*)
    endif

    call MPI_BCAST(nGVecsGlobal, 1, MPI_INTEGER, root, worldComm, ierr)
    call MPI_BCAST(gVecMillerIndicesGlobal, size(gVecMillerIndicesGlobal), MPI_INTEGER, root, worldComm, ierr)


    if (ionode) then
      write(iostd,*)
      write(iostd,*) "***************"
      write(iostd,*) "Distributing G-vecs over processors"
    endif

    call distributeGvecsOverProcessors(nGVecsGlobal, gVecMillerIndicesGlobal, gIndexLocalToGlobal, mill_local, nGVecsLocal)
      !! * Split up the G-vectors and Miller indices over processors 

    if (ionode) write(iostd,*) "Calculating G-vectors"

    allocate(gVecInCart(3,nGVecsLocal))

    do ig = 1, nGVecsLocal

      do ix = 1, 3
        !! * Calculate \(G = m_1b_1 + m_2b_2 + m_3b_3\)

        gVecInCart(ix,ig) = sum(mill_local(:,ig)*recipLattVec(ix,:))

      enddo
      
    enddo

    if (ionode) then
      write(iostd,*) "***************"
      write(iostd,*)
    endif

    deallocate(mill_local)

    return
  end subroutine calculateGvecs

!----------------------------------------------------------------------------
  subroutine distributeGvecsOverProcessors(nGVecsGlobal, gVecMillerIndicesGlobal, gIndexLocalToGlobal, mill_local, nGVecsLocal)
    !! Figure out how many G-vectors there should be per processor.
    !! G-vectors are split up in a round robin fashion over processors
    !! in a single k-point pool.
    !!
    !! <h2>Walkthrough</h2>
    !!

    implicit none

    ! Input variables:
    integer, intent(in) :: nGVecsGlobal
      !! Global number of G-vectors
    !integer, intent(in) :: nProcPerPool
      ! Number of processes per pool
    integer, intent(in) :: gVecMillerIndicesGlobal(3,nGVecsGlobal)
      !! Integer coefficients for G-vectors on all processors

    
    ! Output variables:
    integer, allocatable, intent(out) :: gIndexLocalToGlobal(:)
      !! Converts local index `ig` to global index
    integer, allocatable, intent(out) :: mill_local(:,:)
      !! Integer coefficients for G-vectors
    integer, intent(out) :: nGVecsLocal
      !! Local number of G-vectors on this processor


    ! Local variables:
    integer :: ig_l, ig_g
      !! Loop indices
    integer :: ngr
      !! Number of G-vectors left over after evenly divided across processors


    if( nGVecsGlobal > 0 ) then
      nGVecsLocal = nGVecsGlobal/nProcPerPool
        !!  * Calculate number of G-vectors per processor

      ngr = nGVecsGlobal - nGVecsLocal*nProcPerPool 
        !! * Calculate the remainder

      if( indexInPool < ngr ) nGVecsLocal = nGVecsLocal + 1
        !! * Assign the remainder to the first `ngr` processors

      !> * Generate an array to map a local index
      !>   (`ig` passed to `gIndexLocalToGlobal`) to a global
      !>   index (the value stored at `gIndexLocalToGlobal(ig)`)
      !>   and get local miller indices
      allocate(gIndexLocalToGlobal(nGVecsLocal))
      allocate(mill_local(3,nGVecsLocal))

      ig_l = 0
      do ig_g = 1, nGVecsGlobal

        if(indexInPool == mod(ig_g-1,nProcPerPool)) then
        
          ig_l = ig_l + 1
          gIndexLocalToGlobal(ig_l) = ig_g
          mill_local(:,ig_l) = gVecMillerIndicesGlobal(:,ig_g)

        endif

      enddo

      if (ig_l /= nGVecsLocal) call exitError('distributeGvecsOverProcessors', 'unexpected number of G-vecs for this processor', 1)

    endif

    return
  end subroutine distributeGvecsOverProcessors

!----------------------------------------------------------------------------
  subroutine reconstructFFTGrid(nGVecsLocal, gIndexLocalToGlobal, nKPoints, nPWs1kGlobal, kPosition, gVecInCart, recipLattVec, wfcVecCut, gKIndexGlobal, &
      gKIndexLocalToGlobal, gKIndexOrigOrderLocal, gKSort, gToGkIndexMap, maxGIndexGlobal, maxGkVecsLocal, maxNumPWsGlobal, maxNumPWsPool, &
      nGkLessECutGlobal, nGkLessECutLocal, nGkVecsLocal)
    !! Determine which G-vectors result in \(G+k\)
    !! below the energy cutoff for each k-point and
    !! sort the indices based on \(|G+k|^2\)
    !!
    !! <h2>Walkthrough</h2>
    !!

    implicit none

    ! Input variables:
    integer, intent(in) :: nGVecsLocal
      !! Number of G-vectors on this processor
    integer, intent(in) :: gIndexLocalToGlobal(nGVecsLocal)
      ! Converts local index `ig` to global index
    integer, intent(in) :: nKPoints
      !! Total number of k-points
    !integer, intent(in) :: nkPerPool
      ! Number of k-points in each pool
    integer, intent(in) :: nPWs1kGlobal(nKPoints)
      !! Input number of plane waves for a single k-point

    real(kind=dp), intent(in) :: kPosition(3,nKPoints)
      !! Position of k-points in reciprocal space
    real(kind=dp), intent(in) :: gVecInCart(3,nGVecsLocal)
      !! G-vectors in Cartesian coordinates
    real(kind=dp), intent(in) :: recipLattVec(3,3)
      !! Reciprocal lattice vectors
    real(kind=dp), intent(in) :: wfcVecCut
      !! Energy cutoff converted to vector cutoff


    ! Output variables:
    integer, allocatable, intent(out) :: gKIndexGlobal(:,:)
      !! Indices of \(G+k\) vectors for each k-point
      !! and all processors
    integer, allocatable, intent(out) :: gKIndexLocalToGlobal(:,:)
      !! Local to global indices for \(G+k\) vectors 
      !! ordered by magnitude at a given k-point
    integer, allocatable, intent(out) :: gKIndexOrigOrderLocal(:,:)
      !! Indices of \(G+k\) vectors in just this pool
      !! and for local PWs in the original order
    integer, allocatable, intent(out) :: gKSort(:,:)
      !! Indices to recover sorted order on reduced
      !! \(G+k\) grid
    integer, allocatable, intent(out) :: gToGkIndexMap(:,:)
      !! Index map from \(G\) to \(G+k\);
      !! indexed up to `nGVecsLocal` which
      !! is greater than `maxNumPWsPool` and
      !! stored for each k-point
    integer, intent(out) :: maxGIndexGlobal
      !! Maximum G-vector index among all \(G+k\)
      !! and processors
    integer, intent(out) :: maxGkVecsLocal
      !! Max number of G+k vectors across all k-points
      !! in this pool
    integer, intent(out) :: maxNumPWsGlobal
      !! Max number of \(G+k\) vectors with magnitude
      !! less than `wfcVecCut` among all k-points
    integer, intent(out) :: maxNumPWsPool
      !! Maximum number of \(G+k\) vectors
      !! across all k-points for just this 
      !! pool
    integer, allocatable, intent(out) :: nGkLessECutGlobal(:)
      !! Global number of \(G+k\) vectors with magnitude
      !! less than `wfcVecCut` for each k-point
    integer, allocatable, intent(out) :: nGkLessECutLocal(:)
      !! Number of \(G+k\) vectors with magnitude
      !! less than `wfcVecCut` for each
      !! k-point, on this processor
    integer, allocatable, intent(out) :: nGkVecsLocal(:)
      !! Local number of G-vectors on this processor


    ! Local variables:
    real(kind=dp) :: eps8 = 1.0E-8_dp
      !! Double precision zero
    real(kind=dp) :: gkMod(nkPerPool,nGVecsLocal)
      !! \(|G+k|^2\);
      !! only stored if less than `wfcVecCut`
    real(kind=dp) :: q
      !! \(|q|^2\) where \(q = G+k\)
    real(kind=dp), allocatable :: realGKOrigOrder(:)
      !! Indices of \(G+k\) in original order
    real(kind=dp), allocatable :: realiMillGk(:)
      !! Indices of miller indices after sorting
    real(kind=dp) :: xkCart(3)
      !! Cartesian coordinates for given k-point

    integer :: ik, ig, ix
      !! Loop indices
    integer, allocatable :: gKIndexOrigOrderGlobal(:,:)
      !! Indices of \(G+k\) vectors for each k-point
      !! and all processors in the original order
    integer, allocatable :: igk(:)
      !! Index map from \(G\) to \(G+k\)
      !! indexed up to `maxNumPWsPool`
    integer :: ngk_tmp
      !! Temporary variable to hold `nGkLessECutLocal`
      !! value so that don't have to keep accessing
      !! array
    integer :: maxGIndexLocal
      !! Maximum G-vector index among all \(G+k\)
      !! for just this processor
    integer :: maxNumPWsLocal
      !! Maximum number of \(G+k\) vectors
      !! across all k-points for just this 
      !! processor

    allocate(nGkLessECutLocal(nkPerPool))
    allocate(gToGkIndexMap(nkPerPool,nGVecsLocal))
    
    maxNumPWsLocal = 0
    nGkLessECutLocal(:) = 0
    gToGkIndexMap(:,:) = 0

    if (ionode) then
      write(iostd,*)
      write(iostd,*) "***************"
      write(iostd,*) "Determining G+k combinations less than energy cutoff"
    endif

    do ik = 1, nkPerPool
      !! * For each \(G+k\) combination, calculate the 
      !!   magnitude and, if it is less than the energy
      !!   cutoff, store the G index and magnitude and 
      !!   increment the number of \(G+k\) vectors at
      !!   this k-point. Also, keep track of the maximum 
      !!   number of \(G+k\) vectors among all k-points
      !!
      !! @note
      !!  All of the above calculations are local to a single
      !!  processor.
      !! @endnote

      if (ionode) write(iostd,*) "Processing k-point ", ik

      do ix = 1, 3
        xkCart(ix) = sum(kPosition(:,ik+ikStart_pool-1)*recipLattVec(ix,:))
      enddo

      ngk_tmp = 0

      do ig = 1, nGVecsLocal

        q = sqrt(sum((xkCart(:) + gVecInCart(:,ig))**2))
          ! Calculate \(|G+k|\)

        if (q <= eps8) q = 0.d0

        if (q <= wfcVecCut) then

          ngk_tmp = ngk_tmp + 1
            ! If \(|G+k| \leq \) `wfcVecCut` increment the count for
            ! this k-point

          gkMod(ik,ngk_tmp) = q
            ! Store the modulus for sorting

          gToGkIndexMap(ik,ngk_tmp) = ig
            ! Store the index for this G-vector

        !else

          !if (sqrt(sum(gVecInCart(:, ig)**2)) .gt. &
            !sqrt(sum(kPosition(:,ik+ikStart_pool-1)**2) + sqrt(wfcVecCut))) goto 100
            ! if |G| > |k| + sqrt(Ecut)  stop search
            !! @todo Figure out if there is valid exit check for `ig` loop @endtodo

        endif
      enddo

      if (ngk_tmp == 0) call exitError('reconstructFFTGrid', 'no G+k vectors on this processor', 1) 

100   maxNumPWsLocal = max(maxNumPWsLocal, ngk_tmp)
        ! Track the maximum number of \(G+k\)
        ! vectors among all k-points

      nGkLessECutLocal(ik) = ngk_tmp
        ! Store the total number of \(G+k\)
        ! vectors for this k-point

    enddo

    allocate(nGkLessECutGlobal(nKPoints))
    nGkLessECutGlobal = 0
    nGkLessECutGlobal(ikStart_pool:ikEnd_pool) = nGkLessECutLocal(1:nkPerPool)
    CALL mpiSumIntV(nGkLessECutGlobal, worldComm)
      !! * Calculate the global number of \(G+k\) 
      !!   vectors for each k-point
      
    if (ionode) then

      do ik = 1, nKPoints

        if (nGkLessECutGlobal(ik) .ne. nPWs1kGlobal(ik)) call exitError('reconstructFFTGrid', &
          'computed no. of G-vectors != input no. of plane waves', 1)
          !! * Make sure that number of G-vectors isn't higher than the calculated maximum

      enddo
    endif

    if (ionode) then
      write(iostd,*) "Done determining G+k combinations less than energy cutoff"
      write(iostd,*) "***************"
      write(iostd,*)
    endif

    if (maxNumPWsLocal <= 0) call exitError('reconstructFFTGrid', &
                'No plane waves found: running on too many processors?', 1)
      !! * Make sure that each processor gets some \(G+k\) vectors. If not,
      !!   should rerun with fewer processors.

    call MPI_ALLREDUCE(maxNumPWsLocal, maxNumPWsPool, 1, MPI_INTEGER, MPI_MAX, intraPoolComm, ierr)
    if(ierr /= 0) call exitError('reconstructFFTGrid', 'error in mpi_allreduce 1', ierr)
      !! * When using pools, set `maxNumPWsPool` to the maximum value of `maxNumPWsLocal` 
      !!   in the pool 


    allocate(gKIndexLocalToGlobal(maxNumPWsPool,nkPerPool))
    allocate(igk(maxNumPWsPool))

    gKIndexLocalToGlobal = 0
    igk = 0

    if (ionode) then
      write(iostd,*)
      write(iostd,*) "***************"
      write(iostd,*) "Sorting G+k combinations by magnitude"
    endif


    do ik = 1, nkPerPool
      !! * Reorder the indices of the G-vectors so that
      !!   they are sorted by \(|G+k|^2\) for each k-point

      ngk_tmp = nGkLessECutLocal(ik)

      igk(1:ngk_tmp) = gToGkIndexMap(ik,1:ngk_tmp)

      call hpsort_eps(ngk_tmp, gkMod(ik,:), igk, eps8)
        ! Order vector `igk` by \(|G+k|\) (`gkMod`)

      do ig = 1, ngk_tmp
        
        gKIndexLocalToGlobal(ig,ik) = gIndexLocalToGlobal(igk(ig))
        
      enddo
     
      gKIndexLocalToGlobal(ngk_tmp+1:maxNumPWsPool, ik) = 0

    enddo


    if (ionode) then
      write(iostd,*) "Done sorting G+k combinations by magnitude"
      write(iostd,*) "***************"
      write(iostd,*)
    endif

    deallocate(igk)


    maxGIndexLocal = maxval(gKIndexLocalToGlobal(:,:))
    call MPI_ALLREDUCE(maxGIndexLocal, maxGIndexGlobal, 1, MPI_INTEGER, MPI_MAX, worldComm, ierr)
    if(ierr /= 0) call exitError('reconstructFFTGrid', 'error in mpi_allreduce 2', ierr)
      !! * Calculate the maximum G-vector index 
      !!   among all \(G+k\) and processors

    maxNumPWsGlobal = maxval(nGkLessECutGlobal(1:nKPoints))
      !! * Calculate the maximum number of G-vectors 
      !!   among all k-points

    allocate(gKIndexGlobal(maxNumPWsGlobal, nKPoints))

    if(ionode) then
      write(iostd,*)
      write(iostd,*) "***************"
      write(iostd,*) "Getting global G+k indices"

    endif
  
    gKIndexGlobal(:,:) = 0
    do ik = 1, nKPoints

      if (ionode) write(iostd,*) "Processing k-point ", ik

      call getGlobalGkIndices(nKPoints, maxNumPWsPool, gKIndexLocalToGlobal, ik, nGkLessECutGlobal, nGkLessECutLocal, maxGIndexGlobal, &
          maxNumPWsGlobal, gKIndexGlobal)
        !! * For each k-point, gather all of the \(G+k\) indices
        !!   among all processors in a single global array
    
    enddo

    allocate(gKIndexOrigOrderGlobal(maxNumPWsGlobal, nKPoints))
    allocate(gKSort(maxNumPWsGlobal, nKPoints))

    gKIndexOrigOrderGlobal = gKIndexGlobal
    gKSort = 0._dp

    if(ionode) then

      allocate(realiMillGk(maxNumPWsGlobal))
      allocate(realGKOrigOrder(maxNumPWsGlobal))

      do ik = 1, nKPoints

        realiMillGk = 0._dp
        realGKOrigOrder = 0._dp
        ngk_tmp = nGkLessECutGlobal(ik)

        do ig = 1, ngk_tmp

          realiMillGk(ig) = real(iMill(gKIndexGlobal(ig,ik)))
            !! * Get only the original indices that correspond
            !!   to G vectors s.t. \(|G+k|\) is less than the
            !!   cutoff

          gKSort(ig,ik) = ig
            !! * Initialize an array that will recover the sorted
            !!   order of the G-vectors from only the \(G+k\) sub-grid
            !!   rather than the full G-vector grid like `gKIndexGlobal`

        enddo

        call hpsort_eps(ngk_tmp, realiMillGk(1:ngk_tmp), gKIndexOrigOrderGlobal(1:ngk_tmp,ik), eps8)
          !! * Order the \(G+k\) indices by the original indices `realiMillGk`. 
          !!   This will allow us to recover only specific G-vectors in the 
          !!   original ordering. Have to cast to `real` because that is what the 
          !!   sorting algorithm expects. Would be better to have a different
          !!   interface for different types, but we don't really need that here
          !!   and it shouldn't affect the results. 


        realGKOrigOrder(1:ngk_tmp) = real(gKIndexOrigOrderGlobal(1:ngk_tmp,ik))

        call hpsort_eps(ngk_tmp, realGKOrigOrder(1:ngk_tmp), gKSort(1:ngk_tmp,ik), eps8)
          !! * Sort another index by `gKIndexOrigOrder`. This index will allow
          !!   us to recreate the sorted order on the reduced \(G+k\) grid. We
          !!   need this for outputting the wave functions, projectors, and
          !!   projections in the order that `TME` expects them.

      enddo

      deallocate(realiMillGk)
      deallocate(realGKOrigOrder)
      deallocate(iMill)

    endif

    call MPI_BCAST(gKIndexOrigOrderGlobal, size(gKIndexOrigOrderGlobal), MPI_INTEGER, root, worldComm, ierr)
    call MPI_BCAST(gKSort, size(gKSort), MPI_INTEGER, root, worldComm, ierr)

    call distributeGkVecsInPool(nKPoints, nGkLessECutGlobal, gKIndexOrigOrderGlobal, gKIndexOrigOrderLocal, maxGkVecsLocal, nGkVecsLocal)
      !! * Distribute the G+k vectors evenly across the processes in a single pool

    deallocate(gKIndexOrigOrderGlobal)

    if(ionode) then

      write(iostd,*) "Done getting global G+k indices"
      write(iostd,*) "***************"
      write(iostd,*)
      flush(iostd)

    endif

    return
  end subroutine reconstructFFTGrid

!----------------------------------------------------------------------------
  subroutine distributeGkVecsInPool(nKPoints, nGkLessECutGlobal, gKIndexOrigOrderGlobal, gKIndexOrigOrderLocal, maxGkVecsLocal, nGkVecsLocal)
    !! Distribute the G+k vectors across the pools by 
    !! splitting up the `gKIndexOrigOrderGlobal` array
    !! into local arrays
    !!
    !! <h2>Walkthrough</h2>
    !!

    implicit none

    ! Input variables:
    !integer, intent(in) :: ikEnd_pool
      ! Ending index for k-points in single pool 
    !integer, intent(in) :: ikStart_pool
      ! Starting index for k-points in single pool 
    integer, intent(in) :: nKPoints
      !! Total number of k-points
    !integer, intent(in) :: nkPerPool
      ! Number of k-points in each pool
    integer, intent(in) :: nGkLessECutGlobal(nKPoints)
      !! Global number of G-vectors
    !integer, intent(in) :: nProcPerPool
      ! Number of processes per pool
    integer, intent(in) :: gKIndexOrigOrderGlobal(maxNumPWsGlobal, nKPoints)
      !! Indices of \(G+k\) vectors for each k-point
      !! and all processors in the original order

    
    ! Output variables:
    !integer, allocatable, intent(out) :: iGkEnd_pool(:)
      ! Ending index for G+k vectors on
      ! single process in a given pool
    !integer, allocatable, intent(out) :: iGkStart_pool(:)
      ! Starting index for G+k vectors on
      ! single process in a given pool
    integer, allocatable, intent(out) :: gKIndexOrigOrderLocal(:,:)
      !! Indices of \(G+k\) vectors in just this pool
      !! and for local PWs in the original order
    integer, intent(out) :: maxGkVecsLocal
      !! Max number of G+k vectors across all k-points
      !! in this pool
    integer, allocatable, intent(out) :: nGkVecsLocal(:)
      !! Local number of G-vectors on this processor


    ! Local variables:
    integer :: ik
      !! Loop indices
    integer :: ngkr
      !! Number of G+k vectors left over after evenly 
      !! divided across processors in pool


    allocate(nGkVecsLocal(nkPerPool), iGkStart_pool(nkPerPool), iGkEnd_pool(nkPerPool))

    do ik = 1, nkPerPool
      nGkVecsLocal(ik) = nGkLessECutGlobal(ik+ikStart_pool-1)/nProcPerPool
        !!  * Calculate the number of G+k vectors per processors
        !!    in this pool

      ngkr = nGkLessECutGlobal(ik+ikStart_pool-1) - nGkVecsLocal(ik)*nProcPerPool 
        !! * Calculate the remainder

      if( indexInPool < ngkr ) nGkVecsLocal(ik) = nGkVecsLocal(ik) + 1
        !! * Assign the remainder to the first `ngr` processors

      !>  * Calculate the index of the first G+k vector for this process
      iGkStart_pool(ik) = nGkVecsLocal(ik) * indexInPool + 1
      if( indexInPool >= ngkr ) iGkStart_pool(ik) = iGkStart_pool(ik) + ngkr

      iGkEnd_pool(ik) = iGkStart_pool(ik) + nGkVecsLocal(ik) - 1
        !!  * Calculate the index of the last G+k vector in this pool

    enddo

    maxGkVecsLocal = maxval(nGkVecsLocal)
      !! * Get the max number of G+k vectors across
      !!   all k-points in this pool

    allocate(gKIndexOrigOrderLocal(maxGkVecsLocal, nkPerPool))

    do ik = 1, nkPerPool

      gKIndexOrigOrderLocal(1:nGkVecsLocal(ik),ik) = gKIndexOrigOrderGlobal(iGkStart_pool(ik):iGkEnd_pool(ik),ik+ikStart_pool-1)
        !! * Split up the PWs `gKIndexOrigOrderGlobal` across processors and 
        !!   store the G-vector indices locally

    enddo
      
    return
  end subroutine distributeGkVecsInPool

!----------------------------------------------------------------------------
  subroutine getGlobalGkIndices(nKPoints, maxNumPWsPool, gKIndexLocalToGlobal, ik, nGkLessECutGlobal, nGkLessECutLocal, maxGIndexGlobal, &
      maxNumPWsGlobal, gKIndexGlobal)
    !! Gather the \(G+k\) vector indices in single, global 
    !! array
    !!
    !! <h2>Walkthrough</h2>
    !!

    implicit none

    ! Input variables:
    !integer, intent(in) :: nkPerPool
      ! Number of k-points in each pool
    integer, intent(in) :: nKPoints
      !! Total number of k-points
    integer, intent(in) :: maxNumPWsPool
      !! Maximum number of \(G+k\) vectors
      !! across all k-points for just this 
      !! processor

    integer, intent(in) :: gKIndexLocalToGlobal(maxNumPWsPool, nkPerPool)
      !! Local to global indices for \(G+k\) vectors 
      !! ordered by magnitude at a given k-point;
      !! the first index goes up to `maxNumPWsPool`,
      !! but only valid values are up to `nGkLessECutLocal`
    integer, intent(in) :: ik
      !! Index of current k-point
    integer, intent(in) :: nGkLessECutGlobal(nKPoints)
      !! Global number of \(G+k\) vectors with magnitude
      !! less than `wfcVecCut` for each k-point
    integer, intent(in) :: nGkLessECutLocal(nkPerPool)
      !! Number of \(G+k\) vectors with magnitude
      !! less than `wfcVecCut` for each
      !! k-point, on this processor
    integer, intent(in) :: maxGIndexGlobal
      !! Maximum G-vector index among all \(G+k\)
      !! and processors
    integer, intent(in) :: maxNumPWsGlobal
      !! Max number of \(G+k\) vectors with magnitude
      !! less than `wfcVecCut` among all k-points


    ! Output variables:
    integer, intent(out) :: gKIndexGlobal(maxNumPWsGlobal, nKPoints)
      !! Indices of \(G+k\) vectors for each k-point
      !! and all processors


    ! Local variables:
    integer :: ig
    integer, allocatable :: itmp1(:)
      !! Global \(G+k\) indices for single
      !! k-point with zeros for G-vector indices
      !! where \(G+k\) was greater than the cutoff
    integer :: ngg 
      !! Counter for \(G+k\) vectors for given
      !! k-point; should equal `nGkLessECutGlobal`

    
    allocate(itmp1(maxGIndexGlobal), stat=ierr)
    if (ierr/= 0) call exitError('getGlobalGkIndices','allocating itmp1', abs(ierr))

    itmp1 = 0
    if(ik >= ikStart_pool .and. ik <= ikEnd_pool) then

      do ig = 1, nGkLessECutLocal(ik-ikStart_pool+1)

        itmp1(gKIndexLocalToGlobal(ig, ik-ikStart_pool+1)) = gKIndexLocalToGlobal(ig, ik-ikStart_pool+1)
          !! * For each k-point and \(G+k\) vector for this processor,
          !!   store the local to global indices (`gKIndexLocalToGlobal`) in an
          !!   array that will later be combined globally
          !!
          !! @note
          !!  This will leave zeros in spots where the \(G+k\) 
          !!  combination for this k-point was greater than the energy 
          !!  cutoff.
          !! @endnote

      enddo
    endif

    call mpiSumIntV(itmp1, worldComm)

    ngg = 0
    do  ig = 1, maxGIndexGlobal

      if(itmp1(ig) == ig) then
        !! * Go through and find all of the non-zero
        !!   indices in the now-global `itmp1` array,
        !!   and store them in a new array that won't
        !!   have the extra zeros

        ngg = ngg + 1

        gKIndexGlobal(ngg, ik) = ig

      endif
    enddo


    if(ionode .and. ngg /= nGkLessECutGlobal(ik)) call exitError('writeKInfo', 'Unexpected number of G+k vectors', 1)
      !! * Make sure that the total number of non-zero
      !!   indices matches the global number of \(G+k\)
      !!   vectors for this k-point
    
    deallocate( itmp1 )

    return
  end subroutine getGlobalGkIndices

!----------------------------------------------------------------------------
  subroutine hpsort_eps(n, ra, ind, eps)
    !! Sort an array ra(1:n) into ascending order using heapsort algorithm,
    !! considering two elements equal if their difference is less than `eps`
    !!
    !! n is input, ra is replaced on output by its sorted rearrangement.
    !! Create an index table (ind) by making an exchange in the index array
    !! whenever an exchange is made on the sorted data array (ra).
    !! In case of equal values in the data array (ra) the values in the
    !! index array (ind) are used to order the entries.
    !!
    !! if on input ind(1)  = 0 then indices are initialized in the routine,
    !! if on input ind(1) != 0 then indices are assumed to have been
    !!                initialized before entering the routine and these
    !!                indices are carried around during the sorting process
    !!
    !! To sort other arrays based on the index order in ind, use
    !!      sortedArray(i) = originalArray(ind(i))
    !! If you need to recreate the original array like
    !!      originalArray(i) = sortedArray(indRec(i))
    !! indRec can be generated by sorting a sequential array (routine will
    !! initialize to sequential if not already) based on the order in ind.
    !!      realInd = real(ind)
    !!      hpsort_eps(n, realInd, indRec, eps)
    !!
    !! From QE code, adapted from Numerical Recipes pg. 329 (new edition)
    !!

    implicit none

    ! Input/Output variables:
    real(kind=dp), intent(in) :: eps
    integer, intent(in) :: n

    integer, intent(inout) :: ind(:)
    real(kind=dp), intent(inout) :: ra (:)


    ! Local variables
    integer :: i, ir, j, l, iind
    real(kind=dp) :: rra

    !> Initialize index array, if not already initialized
    if (ind (1) .eq.0) then
      do i = 1, n
        ind(i) = i
      enddo
    endif

    ! nothing to order
    if (n.lt.2) return
    ! initialize indices for hiring and retirement-promotion phase
    l = n / 2 + 1

    ir = n

    sorting: do

      ! still in hiring phase
      if ( l .gt. 1 ) then
        l    = l - 1
        rra  = ra (l)
        iind = ind(l)
        ! in retirement-promotion phase.
      else
        ! clear a space at the end of the array
        rra  = ra (ir)
        !
        iind = ind(ir)
        ! retire the top of the heap into it
        ra (ir) = ra (1)
        !
        ind(ir) = ind(1)
        ! decrease the size of the corporation
        ir = ir - 1
        ! done with the last promotion
        if ( ir .eq. 1 ) then
          ! the least competent worker at all !
          ra (1)  = rra
          !
          ind(1) = iind
          exit sorting
        endif
      endif
      ! wheter in hiring or promotion phase, we
      i = l
      ! set up to place rra in its proper level
      j = l + l
      !
      do while ( j .le. ir )
        if ( j .lt. ir ) then
          ! compare to better underling
          if ( abs(ra(j)-ra(j+1)).ge.eps ) then
            if (ra(j).lt.ra(j+1)) j = j + 1
          else
            ! this means ra(j) == ra(j+1) within tolerance
            if (ind(j) .lt.ind(j + 1) ) j = j + 1
          endif
        endif
        ! demote rra
        if ( abs(rra - ra(j)).ge.eps ) then
          if (rra.lt.ra(j)) then
            ra (i) = ra (j)
            ind(i) = ind(j)
            i = j
            j = j + j
          else
            ! set j to terminate do-while loop
            j = ir + 1
          end if
        else
          !this means rra == ra(j) within tolerance
          ! demote rra
          if (iind.lt.ind(j) ) then
            ra (i) = ra (j)
            ind(i) = ind(j)
            i = j
            j = j + j
          else
            ! set j to terminate do-while loop
            j = ir + 1
          endif
        end if
      enddo
      ra (i) = rra
      ind(i) = iind
    end do sorting
    
    return 
  end subroutine hpsort_eps

!----------------------------------------------------------------------------
  subroutine readPOTCAR(nAtomTypes, VASPDir, pot)
    !! Read PAW pseudopotential information from POTCAR
    !! file
    !!
    !! <h2>Walkthrough</h2>
    !!

    implicit none

    ! Input variables:
    integer, intent(in) :: nAtomTypes
      !! Number of types of atoms

    character(len=256), intent(in) :: VASPDir
      !! Directory with VASP files

    
    ! Output variables:
    type (potcar) :: pot(nAtomTypes)
      !! Holds all information needed from POTCAR


    ! Local variables:
    real(kind=dp) :: dummyD(1000)
      !! Dummy variable to ignore input
    real(kind=dp), allocatable :: dummyDA1(:), dummyDA2(:,:)
      !! Allocatable dummy variable to ignore input
    real(kind=dp) :: H
      !! Factor for generating derivative of 
      !! radial grid

    integer :: angMom
      !! Angular momentum of projectors
    integer :: iT, i, j, ip, ir
      !! Loop indices
    integer :: nProj
      !! Number of projectors with given angular momentum

    character(len=1) :: charSwitch
      !! Switch to determine what section reading
    character(len=256) :: dummyC
      !! Dummy character to ignore input
    character(len=256) :: fileName
      !! Full WAVECAR file name including path

    logical :: found
      !! If the required tag was found


    if(ionode) then
      fileName = trim(VASPDir)//'/POTCAR'

      open(unit=potcarUnit, file=fileName, iostat=ierr, status='old')
      if (ierr .ne. 0) write(iostd,*) 'open error - iostat =', ierr
        !! * If root node, open the `POTCAR` file

      do iT = 1, nAtomTypes

        pot(iT)%nChannels = 0
        pot(iT)%lmmax = 0

        read(potcarUnit,*) dummyC, pot(iT)%element, dummyC
          !! * Read in the header
        read(potcarUnit,*)
          !! * Ignore the valence line
        read(potcarUnit,'(1X,A1)') charSwitch
          !! * Read in character switch to determine if there is a 
          !!   PSCRT section (switch not used)
          !! @note
          !!  Some of the switches do not actually seem to be used
          !!  as a switch because the following code does not include
          !!  any logic to process the switch. If the POTCAR files 
          !!  ever have a different form than assumed here, the logic
          !!  will need to be updated.
          !! @endnote

        found = .false.
        do while (.not. found)
          !! * Ignore all lines until you get to the `END` of
          !!   the PSCRT section
        
          read(potcarUnit, '(A)') dummyC

          if (dummyC(1:3) == 'END') found = .true.
        
        enddo

        read(potcarUnit,'(1X,A1)') charSwitch
          !! * Read character switch (switch not used)
        read(potcarUnit,*)
          !! * Ignore the max G for local potential
        read(potcarUnit,*) (dummyD(i), i=1,1000)
          !! * Ignore the local pseudopotential in reciprocal
          !!   space
        read(potcarUnit,'(1X,A1)') charSwitch
          !! * Read character switch

        if (charSwitch == 'g') then
          !! * Ignore gradient correction

          read(potcarUnit,*)
          read(potcarUnit,'(1X,A1)') charSwitch
          
        endif

        if (charSwitch == 'c') then
          !! * Ignore core charge density

          read(potcarUnit,*) (dummyD(i), i=1,1000)
          read(potcarUnit,'(1X,A1)') charSwitch
          
        endif

        if (charSwitch == 'k') then
          !! * Ignore partial kinetic energy density

          read(potcarUnit,*) (dummyD(i), i=1,1000)
          read(potcarUnit,'(1X,A1)') charSwitch
          
        endif

        if (charSwitch == 'K') then
          !! * Ignore kinetic energy density

          read(potcarUnit,*) (dummyD(i), i=1,1000)
          read(potcarUnit,'(1X,A1)') charSwitch
          
        endif

        read(potcarUnit,*) (dummyD(i), i=1,1000)
          !! * Ignore the atomic pseudo charge density

        read(potcarUnit,*) pot(iT)%maxGkNonlPs, dummyC
          !! * Read the max \(|G+k|\) for non-local potential 
          !!   and ignore unused boolean (`LDUM` in VASP)

        pot(iT)%maxGkNonlPs = pot(iT)%maxGkNonlPs/angToBohr

        read(potcarUnit,'(1X,A1)') charSwitch
          !! * Read character switch

        allocate(dummyDA1(nonlPseudoGridSize))

        do while (charSwitch /= 'D' .and. charSwitch /= 'A' .and. charSwitch /= 'P' &
          .and. charSwitch /= 'E')
            !! * Until you have read in all of the momentum channels
            !!   (i.e. you get to a character switch that is not `'N'`)
            !!     * Read in the angular momentum, the number of 
            !!       projectors at this angular momentum, and the max
            !!       r for the non-local contribution
            !!     * Increment the number of nlm channels
            !!     * Ignore non-local strength multipliers
            !!     * Read in the reciprocal-space projectors and set
            !!       boundary
            !!     * Increment the number of l channels
            !!     * Read the next character switch

          read(potcarUnit,*) angMom, nProj, pot(iT)%psRMax
            ! Read in angular momentum, the number of projectors
            ! at this angular momentum, and the max r for the 
            ! non-local contribution

          pot(iT)%lmmax = pot(iT)%lmmax + (2*angMom+1)*nProj
            ! Increment the number of nlm channels

          allocate(dummyDA2(nProj,nProj))

          read(potcarUnit,*) dummyDA2(:,:)
            ! Ignore non-local strength multipliers

          do ip = 1, nProj
            ! Read in the reciprocal-space and real-space
            ! projectors

            pot(iT)%angMom(pot(iT)%nChannels+ip) = angMom

            read(potcarUnit,*) 
            read(potcarUnit,*) (pot(iT)%recipProj(pot(iT)%nChannels+ip,i), i=1,nonlPseudoGridSize)
              ! Read in reciprocal-space projector
              ! I believe these units are Ang^(3/2). When multiplied by `1/sqrt(omega)`,
              ! the projectors are then unitless. 

            ! Not really sure what the purpose of this is. Seems to be setting the grid boundary,
            ! but I'm not sure on the logic.
            if(mod(angMom,2) == 0) then
              pot(iT)%recipProj(pot(iT)%nChannels+ip, 0) = pot(iT)%recipProj(pot(iT)%nChannels+ip, 2) 
            else
              pot(iT)%recipProj(pot(iT)%nChannels+ip, 0) = -pot(iT)%recipProj(pot(iT)%nChannels+ip, 2) 
            endif

            read(potcarUnit,*) 
            read(potcarUnit,*) (dummyDA1(i), i=1,nonlPseudoGridSize)
              ! Ignore real-space projector

          enddo

          pot(iT)%nChannels = pot(iT)%nChannels + nProj
            ! Increment the number of l channels

          deallocate(dummyDA2)

          read(potcarUnit,'(1X,A1)') charSwitch
            ! Read character switch

        enddo

        deallocate(dummyDA1)

        if (charSwitch /= 'P') then
          !! * Ignore depletion charges

          read(potcarUnit,*)
          read(potcarUnit,*)
          
        else

          read(potcarUnit,*) pot(iT)%nmax, pot(iT)%rAugMax  
            !! * Read the number of mesh grid points and
            !!   the maximum radius in the augmentation sphere

          pot(iT)%rAugMax = pot(iT)%rAugMax*angToBohr 
            ! Convert units 

          read(potcarUnit,*)
            !! * Ignore format specifier
          read(potcarUnit,'(1X,A1)') charSwitch
            !! * Read character switch (not used)

          allocate(pot(iT)%radGrid(pot(iT)%nmax))
          allocate(pot(iT)%dRadGrid(pot(iT)%nmax))
          allocate(pot(iT)%wps(pot(iT)%nChannels,pot(iT)%nmax))
          allocate(pot(iT)%wae(pot(iT)%nChannels,pot(iT)%nmax))
          allocate(dummyDA2(pot(iT)%nChannels, pot(iT)%nChannels))

          read(potcarUnit,*) dummyDA2(:,:)
            !! * Ignore augmentation charges
          read(potcarUnit,'(1X,A1)') charSwitch
            !! * Read character switch

          if (charSwitch == 't') then
            !! * Ignore total charge in each channel 

            read(potcarUnit,*) dummyDA2(:,:)
            read(potcarUnit,*) 

          endif

          read(potcarUnit,*) dummyDA2
            !! * Ignore initial occupancies in atom

          read(potcarUnit,'(1X,A1)') charSwitch
            !! * Read character switch
          if (charSwitch /= 'g') call exitError('readPOTCAR', 'expected grid section', 1)

          read(potcarUnit,*) (pot(iT)%radGrid(i), i=1,pot(iT)%nmax)

          pot(iT)%radGrid(:) = pot(iT)%radGrid(:)*angToBohr

          H = log(pot(iT)%radGrid(pot(iT)%nmax)/pot(iT)%radGrid(1))/(pot(iT)%nmax - 1)
            !! * Calculate \(H\) which is used to generate the derivative of the grid
            !!
            !! @note
            !!  The grid in VASP is defined as \(R_i = R_0e^{H(i-1)}\), so we define the
            !!  derivative as \(dR_i = R_0He^{H(i-1)}\)
            !! @endnote
          
          found = .false.
          do ir = 1, pot(iT)%nmax
            !! * Calculate the max index of the augmentation sphere and
            !!   the derivative of the radial grid

            if (.not. found .and. pot(iT)%radGrid(ir) > pot(iT)%rAugMax) then
              pot(iT)%iRAugMax = ir - 1
              found = .true.
            endif

            pot(iT)%dRadGrid(ir) = pot(iT)%radGrid(1)*H*exp(H*(ir-1))

          enddo

          read(potcarUnit,'(1X,A1)') charSwitch
            !! * Read character switch
          if (charSwitch /= 'a') call exitError('readPOTCAR', 'expected aepotential section', 1)

          allocate(dummyDA1(pot(iT)%nmax))

          read(potcarUnit,*) dummyDA1(:)
            !! * Ignore AE potential

          read(potcarUnit,'(1X,A1)') charSwitch
            !! * Read character switch
          if (charSwitch /= 'c') call exitError('readPOTCAR', 'expected core charge-density section', 1)

          read(potcarUnit,*) dummyDA1(:)
            !! * Ignore the frozen core charge
          read(potcarUnit,'(1X,A1)') charSwitch
            !! * Read character switch

          if (charSwitch == 'k') then
            !! * Ignore kinetic energy density

            read(potcarUnit,*) dummyDA1(:)
            read(potcarUnit,'(1X,A1)') charSwitch

          endif

          if (charSwitch == 'm') then
            !! * Ignore pseudo-ized kinetic energy density

            read(potcarUnit,*) dummyDA1(:)
            read(potcarUnit,'(1X,A1)') charSwitch

          endif

          if (charSwitch == 'l') then
            !! * Ignore local pseudopotential core

            read(potcarUnit,*) dummyDA1(:)
            read(potcarUnit,'(1X,A1)') charSwitch

          endif

          if (charSwitch /= 'p') call exitError('readPOTCAR', 'expected pspotential section', 1)
          
          read(potcarUnit,*) dummyDA1(:)
            !! * Ignore PS potential

          read(potcarUnit,'(1X,A1)') charSwitch
            !! * Read character switch
          if (charSwitch /= 'c') call exitError('readPOTCAR', 'expected core charge-density section', 1)
          
          read(potcarUnit,*) dummyDA1(:)
            !! * Ignore core charge density

          do ip = 1, pot(iT)%nChannels
            !! * Read the AE and PS partial waves for each projector
            
            read(potcarUnit,'(1X,A1)') charSwitch
            if (charSwitch /= 'p') call exitError('readPOTCAR', 'expected pseudowavefunction section', 1)
            read(potcarUnit,*) (pot(iT)%wps(i,ip), i=1,pot(iT)%nmax)

            read(potcarUnit,'(1X,A1)') charSwitch
            if (charSwitch /= 'a') call exitError('readPOTCAR', 'expected aewavefunction section', 1)
            read(potcarUnit,*) (pot(iT)%wae(i,ip), i=1,pot(iT)%nmax)

          enddo

          pot(iT)%wps(:,:) = pot(iT)%wps(:,:)/sqrt(angToBohr)
          pot(iT)%wae(:,:) = pot(iT)%wae(:,:)/sqrt(angToBohr)
            !! @note
            !!  Based on the fact that this does not have an x/y/z
            !!  dimension and that these values get multiplied by 
            !!  `radGrid` and `dRadGrid`, which we treat as being 
            !!  one dimensional, I think these are one dimensional 
            !!  and should just have `1/sqrt(angToBohr)`. That has 
            !!  worked well in the past too.
            !! @endnote

          deallocate(dummyDA1)
          deallocate(dummyDA2)

        endif

        found = .false.
        do while (.not. found)
          !! * Ignore all lines until you get to the `End of Dataset`
        
          read(potcarUnit, '(A)') dummyC

          if (index(dummyC,'End of Dataset') /= 0) found = .true.
        
        enddo

      enddo

    endif    

    do iT = 1, nAtomTypes

      call MPI_BCAST(pot(iT)%nChannels, 1, MPI_INTEGER, root, worldComm, ierr)
      call MPI_BCAST(pot(iT)%lmmax, 1, MPI_INTEGER, root, worldComm, ierr)
      call MPI_BCAST(pot(iT)%maxGkNonlPs, 1, MPI_DOUBLE_PRECISION, root, worldComm, ierr)
      call MPI_BCAST(pot(iT)%angmom, size(pot(iT)%angmom), MPI_INTEGER, root, worldComm, ierr)
      call MPI_BCAST(pot(iT)%recipProj, size(pot(iT)%recipProj), MPI_DOUBLE_PRECISION, root, worldComm, ierr)

    enddo

    return
  end subroutine readPOTCAR

!----------------------------------------------------------------------------
  subroutine projAndWav(fftGridSize, maxGkVecsLocal, maxNumPWsGlobal, nAtoms, nAtomTypes, nBands, nGkVecsLocal, nGVecsGlobal, nKPoints, &
      nRecords, nSpins, gKIndexOrigOrderLocal, gKSort, gVecMillerIndicesGlobal, nPWs1kGlobal, atomPositionsDir, kPosition, omega, &
      recipLattVec, exportDir, VASPDir, gammaOnly, pot)

    use miscUtilities, only: int2str

    implicit none

    ! Input variables: 
    integer, intent(in) :: fftGridSize(3)
      !! Number of points on the FFT grid in each direction
    integer, intent(in) :: maxGkVecsLocal
      !! Max number of G+k vectors across all k-points
      !! in this pool
    integer, intent(in) :: maxNumPWsGlobal
      !! Max number of \(G+k\) vectors with magnitude
      !! less than `wfcVecCut` among all k-points
    integer, intent(in) :: nAtoms
      !! Number of atoms
    integer, intent(in) :: nAtomTypes
      !! Number of types of atoms
    integer, intent(in) :: nBands
      !! Total number of bands
    integer, intent(in) :: nGkVecsLocal(nkPerPool)
      !! Local number of G-vectors on this processor
    integer, intent(in) :: nGVecsGlobal
      !! Global number of G-vectors
    !integer, intent(in) :: nkPerPool
      ! Number of k-points in each pool
    integer, intent(in) :: nKPoints
      !! Total number of k-points
    integer, intent(in) :: nRecords
      !! Number of records in the WAVECAR file
    integer, intent(in) :: nSpins
      !! Number of spins
    integer, intent(in) :: gKIndexOrigOrderLocal(maxGkVecsLocal,nkPerPool)
      !! Indices of \(G+k\) vectors in just this pool
      !! and for local PWs in the original order
    integer, intent(in) :: gKSort(maxNumPWsGlobal, nKPoints)
      !! Indices to recover sorted order on reduced
      !! \(G+k\) grid
    integer, intent(in) :: gVecMillerIndicesGlobal(3,nGVecsGlobal)
      !! Integer coefficients for G-vectors on all processors
    integer, intent(in) :: nPWs1kGlobal(nKPoints)
      !! Input number of plane waves for a single k-point

    real(kind=dp), intent(in) :: atomPositionsDir(3,nAtoms)
      !! Atom positions
    real(kind=dp), intent(in) :: kPosition(3,nKPoints)
      !! Position of k-points in reciprocal space
    real(kind=dp), intent(in) :: omega
      !! Volume of unit cell
    real(kind=dp), intent(in) :: recipLattVec(3,3)
      !! Reciprocal lattice vectors

    character(len=256), intent(in) :: exportDir
      !! Directory to be used for export
    character(len=256), intent(in) :: VASPDir
      !! Directory with VASP files

    logical, intent(in) :: gammaOnly
      !! If the gamma only VASP code is used

    type (potcar) :: pot(nAtomTypes)
      !! Holds all information needed from POTCAR

    ! Local variables:
    integer, allocatable :: gKIndexOrigOrderLocal_ik(:)
      !! Indices of \(G+k\) vectors in just this pool
      !! and for local PWs in the original order for a
      !! given k-point
    integer :: nGkVecsLocal_ik
      !! Number of G+k vectors locally for 
      !! a given k-point
    integer :: nPWs1k
      !! Input number of plane waves for the given k-point
    integer :: irec
      !! Record number in WAVECAR file;
      !! needed for shared access
    integer :: ikLocal, ikGlobal, isp, isk
      !! Loop indices

    real(kind=dp), allocatable :: realProjWoPhase(:,:,:)
      !! Real projectors without phase

    complex*8, allocatable :: coeffLocal(:,:)
      !! Plane wave coefficients
    complex(kind=dp) :: compFact(64,nAtomTypes)
      !! Complex "phase" factor
    complex(kind=dp), allocatable :: phaseExp(:,:)
      !! Complex phase exponential

    character(len=256) :: fileName
      !! Full WAVECAR file name including path

    
    if(indexInPool == 0) then
      !! Have the root node in each pool open the WAVECAR file

      fileName = trim(VASPDir)//'/WAVECAR'

      open(unit=wavecarUnit, file=fileName, access='direct', recl=nRecords, iostat=ierr, status='old', SHARED)
      if (ierr .ne. 0) write(iostd,*) 'open error - iostat =', ierr

    endif

    do ikLocal = 1, nkPerPool
      nGkVecsLocal_ik = nGkVecsLocal(ikLocal)

      allocate(phaseExp(nGkVecsLocal_ik, nAtoms))
      allocate(realProjWoPhase(nGkVecsLocal_ik, 64, nAtomTypes))
      allocate(coeffLocal(nGkVecsLocal_ik, nBands))
      allocate(gKIndexOrigOrderLocal_ik(nGkVecsLocal_ik))

      gKIndexOrigOrderLocal_ik = gKIndexOrigOrderLocal(1:nGkVecsLocal_ik,ikLocal)

      ikGlobal = ikLocal+ikStart_pool-1
        !! Get the global `ik` index from the local one

      nPWs1k = nPWs1kGlobal(ikGlobal)

      !> Calculate the projectors and phase only once for each k-point
      !> because they are not dependent on spin. Write them out as if 
      !> they were dependent on spin because that is how TME currently
      !> expects it.
      call calculatePhase(ikLocal, nAtoms, nGkVecsLocal_ik, nGVecsGlobal, nKPoints, gKIndexOrigOrderLocal_ik, gVecMillerIndicesGlobal, &
                atomPositionsDir, phaseExp)

      call calculateRealProjWoPhase(fftGridSize, ikLocal, nAtomTypes, nGkVecsLocal_ik, nKPoints, gKIndexOrigOrderLocal_ik, gVecMillerIndicesGlobal, &
                kPosition, omega, recipLattVec, gammaOnly, pot, realProjWoPhase, compFact)

      if(indexInPool == 0) write(*,'("    Writing projectors of k-point ", i3)') ikGlobal

      call writeProjectors(ikLocal, nAtoms, iType, maxNumPWsGlobal, nAtomTypes, nAtomsEachType, nGkVecsLocal_ik, nKPoints, nPWs1k, & 
                gKSort, realProjWoPhase, compFact, phaseExp, exportDir, pot)

      do isp = 1, nSpins

        isk = ikGlobal + (isp - 1)*nKPoints
          !! Define index to combine k-point and spin

        irec = 2 + isk + (isk - 1)*nBands
          ! Have all processes increment the record number so
          ! they know where they are supposed to access the WAVECAR
          ! once/if they are the I/O node

        if(indexInPool == 0) write(*,'("    Reading and writing wave function for k-point ", i3, " and spin ", i2)') ikGlobal, isp

        call readAndWriteWavefunction(ikLocal, isp, maxNumPWsGlobal, nBands, nGkVecsLocal_ik, nKPoints, nPWs1k, gKSort, exportDir, irec, coeffLocal)

        if(indexInPool == 0) write(*,'("    Getting and writing projections for k-point ", i3, " and spin ", i2)') ikGlobal, isp

        call getAndWriteProjections(ikGlobal, isp, nAtoms, nAtomTypes, nAtomsEachType, nBands, nGkVecsLocal_ik, nKPoints, realProjWoPhase, compFact, & 
                  phaseExp, coeffLocal, exportDir, pot)

      enddo

      deallocate(phaseExp, realProjWoPhase, coeffLocal, gKIndexOrigOrderLocal_ik)
    enddo

    if(indexInPool == 0) close(wavecarUnit)

    return
  end subroutine projAndWav

!----------------------------------------------------------------------------
  subroutine calculatePhase(ik, nAtoms, nGkVecsLocal_ik, nGVecsGlobal, nKPoints, gKIndexOrigOrderLocal_ik, gVecMillerIndicesGlobal, &
                atomPositionsDir, phaseExp)
    implicit none

    ! Input variables: 
    integer, intent(in) :: ik
      !! Current k-point
    integer, intent(in) :: nAtoms
      !! Number of atoms
    integer, intent(in) :: nGkVecsLocal_ik
      !! Local number of G-vectors on this processor
      !! for a given k-point
    integer, intent(in) :: nGVecsGlobal
      !! Global number of G-vectors
    !integer, intent(in) :: nkPerPool
      ! Number of k-points in each pool
    integer, intent(in) :: nKPoints
      !! Total number of k-points
    integer, intent(in) :: gKIndexOrigOrderLocal_ik(nGkVecsLocal_ik)
      !! Indices of \(G+k\) vectors in just this pool
      !! and for local PWs in the original order for a 
      !! given k-point
    integer, intent(in) :: gVecMillerIndicesGlobal(3,nGVecsGlobal)
      !! Integer coefficients for G-vectors on all processors

    real(kind=dp), intent(in) :: atomPositionsDir(3,nAtoms)
      !! Atom positions

    ! Output variables:
    complex(kind=dp), intent(out) :: phaseExp(nGkVecsLocal_ik,nAtoms)

    ! Local variables:
    integer :: ia, ipw
      !! Loop indices

    real(kind=dp) :: atomPosDir(3)
      !! Direct coordinates for current atom

    complex(kind=dp) :: expArg
      !! Argument for phase exponential
    complex(kind=dp) :: itwopi = (0._dp, 1._dp)*twopi
      !! Complex phase exponential
    
    do ia = 1, nAtoms

      atomPosDir = atomPositionsDir(:,ia)
        !! Store positions locally so don't have to access 
        !! array every loop over plane waves

      do ipw = 1, nGkVecsLocal_ik

        expArg = itwopi*sum(atomPosDir(:)*gVecMillerIndicesGlobal(:,gKIndexOrigOrderLocal_ik(ipw)))
          !! \(2\pi i (\mathbf{G} \cdot \mathbf{r})\)

        phaseExp(ipw, ia) = exp(expArg)

      enddo
    enddo

    return
  end subroutine calculatePhase

!----------------------------------------------------------------------------
  subroutine calculateRealProjWoPhase(fftGridSize, ik, nAtomTypes, nGkVecsLocal_ik, nKPoints, gKIndexOrigOrderLocal_ik, gVecMillerIndicesGlobal, &
      kPosition, omega, recipLattVec, gammaOnly, pot, realProjWoPhase, compFact)
    implicit none

    ! Input variables:
    integer, intent(in) :: fftGridSize(3)
      !! Number of points on the FFT grid in each direction
    integer, intent(in) :: ik
      !! Current k-point 
    integer, intent(in) :: nAtomTypes
      !! Number of types of atoms
    integer, intent(in) :: nGkVecsLocal_ik
      !! Local number of G-vectors on this processor
      !! for a given k-point
    !integer, intent(in) :: nkPerPool
      ! Number of k-points in each pool
    integer, intent(in) :: nKPoints
      !! Total number of k-points
    integer, intent(in) :: gKIndexOrigOrderLocal_ik(nGkVecsLocal_ik)
      !! Indices of \(G+k\) vectors in just this pool
      !! and for local PWs in the original order for a
      !! given k-point
    integer, intent(in) :: gVecMillerIndicesGlobal(3,nGVecsGlobal)
      !! Integer coefficients for G-vectors on all processors

    real(kind=dp), intent(in) :: kPosition(3,nKPoints)
      !! Position of k-points in reciprocal space
    real(kind=dp), intent(in) :: omega
      !! Volume of unit cell
    real(kind=dp), intent(in) :: recipLattVec(3,3)
      !! Reciprocal lattice vectors

    logical, intent(in) :: gammaOnly
      !! If the gamma only VASP code is used

    type (potcar) :: pot(nAtomTypes)
      !! Holds all information needed from POTCAR

    ! Output variables:
    real(kind=dp), intent(out) :: realProjWoPhase(nGkVecsLocal_ik,64,nAtomTypes)
      !! Real projectors without phase

    complex(kind=dp), intent(out) :: compFact(64,nAtomTypes)
      !! Complex "phase" factor

    ! Local variables:
    integer :: angMom
      !! Angular momentum of projectors
    integer :: ilm
      !! Index to track going over l and m
    integer :: ilmBase
      !! Starting index over l and m based 
      !! on the current angular momentum
    integer :: ilmMax
      !! Max index over l and m based 
      !! on the current angular momentum
    integer :: imMax
      !! Max index of magnetic quantum number;
      !! loop from 0 to `imMax=2*angMom` because
      !! \(m_l\) can go from \(-l, \dots, l \)
    integer :: YDimL
      !! L dimension of spherical harmonics;
      !! max l quantum number across all
      !! pseudopotentials
    integer :: YDimLM
      !! Total number of lm combinations
    integer :: iT, ip, im, ipw
      !! Loop index
      
    real(kind=dp) :: gkMod(nGkVecsLocal_ik)
      !! \(|G+k|^2\)
    real(kind=dp) :: gkUnit(3,nGkVecsLocal_ik)
      !! \( (G+k)/|G+k| \)
    real(kind=dp) :: multFact(nGkVecsLocal_ik)
      !! Multiplicative factor for the pseudopotential;
      !! only used in the Gamma-only version
    real(kind=dp), allocatable :: pseudoV(:)
      !! Pseudopotential
    real(kind=dp), allocatable :: Ylm(:,:)
      !! Spherical harmonics


    call generateGridTable(fftGridSize, nGkVecsLocal_ik, nKPoints, gKIndexOrigOrderLocal_ik, gVecMillerIndicesGlobal, ik, kPosition, &
          recipLattVec, gammaOnly, gkMod, gkUnit, multFact)

    YDimL = maxL(nAtomTypes, pot)
      !! Get the L dimension for the spherical harmonics by
      !! finding the max l quantum number across all pseudopotentials

    YDimLM = (YDimL + 1)**2
      !! Calculate the total number of lm pairs

    allocate(Ylm(nGkVecsLocal_ik, YDimLM))

    call getYlm(nGkVecsLocal_ik, YDimL, YDimLM, gkUnit, Ylm)

    do iT = 1, nAtomTypes
      ilm = 1

      do ip = 1, pot(iT)%nChannels

        call getPseudoV(ip, nGkVecsLocal_ik, gkMod, multFact, omega, pot(iT), pseudoV)

        angMom = pot(iT)%angMom(ip)
        imMax = 2*angMom
        ilmBase = angMom**2 + 1

        !> Store complex phase factor
        ilmMax = ilm + imMax
        if(angMom == 0) then
          compFact(ilm:ilmMax,iT) = 1._dp
        else if(angMom == 1) then
          compFact(ilm:ilmMax,iT) = (0._dp, 1._dp)
        else if(angMom == 2) then
          compFact(ilm:ilmMax,iT) = -1._dp
        else if(angMom == 3) then
          compFact(ilm:ilmMax,iT) = (0._dp, -1._dp)
        endif

        do im = 0, imMax
          
          do ipw = 1, nGkVecsLocal_ik

            realProjWoPhase(ipw,ilm+im,iT) = pseudoV(ipw)*Ylm(ipw,ilmBase+im)
              !! @note
              !!  This code does not work with spin spirals! For that to work, would need 
              !!  an additional index at the end of the array for `ISPINOR`.
              !! @endnote
              !!
              !! @todo Add test to kill job if `NONL_S%LSPIRAL = .TRUE.` @endtodo
              !!
              !! @note
              !!  `realProjWoPhase` corresponds to `QPROJ`, but it only stores as much as needed 
              !!  for our application.
              !! @endnote
              !!
              !! @note
              !!  `QPROJ` is accessed as `QPROJ(ipw,ilm,iT,ik,1)`, where `ipw` is over the number
              !!  of plane waves at a specfic k-point, `ilm` goes from 1 to `WDES%LMMAX(iT)` and
              !!  `iT` is the atom-type index.
              !! @endnote
              !!
              !! @note
              !!  At the end of the subroutine `STRENL` in `nonl.F` that calculates the forces,
              !!  `SPHER` is called with `IZERO=1` along with the comment "relalculate the 
              !!  projection operators (the array was used as a workspace)." `SPHER` is what is
              !!  used to calculate `QPROJ`.
              !!
              !!  Based on this comment, I am going to assume `IZERO = 1`, which means that
              !!  `realProjWoPhase` is calculated directly rather than being added to what was
              !!  previously stored in the array, as is done in the `SPHER` subroutine.
              !! @endnote
          enddo
        enddo
        
        deallocate(pseudoV)

        ilm = ilm + imMax + 1

      enddo

      if(ilm - 1 /= pot(iT)%lmmax) call exitError('calculatePseudoTimesYlm', 'LMMAX is wrong', 1)

    enddo

    deallocate(Ylm)

    return
  end subroutine calculateRealProjWoPhase

!----------------------------------------------------------------------------
  subroutine generateGridTable(fftGridSize, nGkVecsLocal_ik, nKPoints, gKIndexOrigOrderLocal_ik, gVecMillerIndicesGlobal, ik, kPosition, &
        recipLattVec, gammaOnly, gkMod, gkUnit, multFact)
    implicit none

    ! Input variables:
    integer, intent(in) :: fftGridSize(3)
      !! Number of points on the FFT grid in each direction
    integer, intent(in) :: nGkVecsLocal_ik
      !! Local number of G-vectors on this processor
      !! for a given k-point
    !integer, intent(in) :: nkPerPool
      ! Number of k-points in each pool
    integer, intent(in) :: nKPoints
      !! Total number of k-points
    integer, intent(in) :: gKIndexOrigOrderLocal_ik(nGkVecsLocal_ik)
      !! Indices of \(G+k\) vectors in just this pool
      !! and for local PWs in the original order for a
      !! given k-point
    integer, intent(in) :: gVecMillerIndicesGlobal(3,nGVecsGlobal)
      !! Integer coefficients for G-vectors on all processors
    integer, intent(in) :: ik
      !! Current k-point 

    real(kind=dp), intent(in) :: kPosition(3,nKPoints)
      !! Position of k-points in reciprocal space
    real(kind=dp), intent(in) :: recipLattVec(3,3)
      !! Reciprocal lattice vectors

    logical, intent(in) :: gammaOnly
      !! If the gamma only VASP code is used

    ! Output variables:
    real(kind=dp), intent(out) :: gkMod(nGkVecsLocal_ik)
      !! \(|G+k|^2\)
    real(kind=dp), intent(out) :: gkUnit(3,nGkVecsLocal_ik)
      !! \( (G+k)/|G+k| \)
    real(kind=dp), intent(out) :: multFact(nGkVecsLocal_ik)
      !! Multiplicative factor for the pseudopotential;
      ! only used in the Gamma-only version

    ! Local variables:
    integer :: gVec(3)
      !! Local storage of this G-vector
    integer :: ipw, ix
      !! Loop indices

    real(kind=dp) :: gkCart(3)
      !! \(G+k\) in Cartesian coordinates for only
      !! vectors that satisfy the cutoff
    real(kind=dp) :: gkDir(3)
      !! \(G+k\) in direct coordinates for only
      !! vectors that satisfy the cutoff


    multFact(:) = 1._dp
      !! Initialize the multiplicative factor to 1

    do ipw = 1, nGkVecsLocal_ik

      !N1 = MOD(WDES%IGX(ipw,ik) + fftGridSize(1), fftGridSize(1)) + 1
      !N2 = MOD(WDES%IGY(ipw,ik) + fftGridSize(2), fftGridSize(2)) + 1
      !N3 = MOD(WDES%IGZ(ipw,ik) + fftGridSize(3), fftGridSize(3)) + 1

      !G1 = (GRID%LPCTX(N1) + kPosition(1,ik))
      !G2 = (GRID%LPCTY(N2) + kPosition(2,ik))
      !G3 = (GRID%LPCTZ(N3) + kPosition(3,ik))
        ! @note
        !  The original code from VASP is left commented out above. 
        !  `GRID%LPCT*` corresponds to our `gVecMillerIndicesGlobal_tmp`
        !  variable that holds the unsorted G-vectors in Miller indices. 
        !  `WDES%IGX/IGY/IGZ` holds only the G-vectors s.t. \(|G+k| <\)
        !  cutoff. Their values do not seem to be sorted, so I use 
        !  `gKIndexOrigOrderGlobal` to recreate the unsorted order from
        !  the sorted array.
        ! @endnote


      gVec(:) = gVecMillerIndicesGlobal(:,gKIndexOrigOrderLocal_ik(ipw))
      gkDir(:) = gVec(:) + kPosition(:,ik+ikStart_pool-1)
        ! I belive this recreates the purpose of the original lines 
        ! above by getting \(G+k\) in direct coordinates for only
        ! the \(G+k\) combinations that satisfy the cutoff

      !IF (ASSOCIATED(NONL_S%VKPT_SHIFT)) THEN
        ! @note 
        !  `NONL_S%VKPT_SHIFT` is only set in `us.F::SETDIJ_AVEC_`.
        !  That subroutine is only called in `nmr.F::SETDIJ_AVEC`, but
        !  that call is only reached if `ORBITALMAG = .TRUE.`. This value
        !  can be set in the `INCAR` file, but there is no wiki entry,
        !  so it looks like a legacy option. Not sure how it relates
        !  to other magnetic switches like `MAGMOM`. However, `ORBITALMAG`
        !  is written to the `vasprun.xml` file, so will just test
        !  to make sure that `ORBITALMAG = .FALSE.` and throw an error 
        !  if not.
        ! @endnote

      if(gammaOnly .and. (gVec(1) /= 0 .or. gVec(2) /= 0 .or. gVec(3) /= 0)) multFact(ipw) = sqrt(2._dp)

      do ix = 1, 3
        gkCart(ix) = sum(gkDir(:)*recipLattVec(ix,:))
          ! VASP has a factor of `twopi` here, but I removed
          ! it because the vectors in `reconstructFFTGrid` 
          ! do not have that factor, but they result in the
          ! number of \(G+k\) vectors for each k-point matching
          ! the value input from the WAVECAR.
      enddo
        !! @note
        !!  There was originally a subtraction within the parentheses of `QX`/`QY`/`QZ`
        !!  representing the spin spiral propagation vector. It was removed here because 
        !!  we do not consider spin spirals.
        !! @endnote


      gkMod(ipw) = max(sqrt(sum(gkCart(:)**2 )), 1e-10_dp)
        !! * Get magnitude of G+k vector 

      gkUnit(:,ipw)  = gkCart(:)/gkMod(ipw)
        !! * Calculate unit vector in direction of \(G+k\)

      !IF (PRESENT(DK)) THEN
        !! @note
        !!  At the end of the subroutine `STRENL` in `nonl.F` that calculates the forces,
        !!  `SPHER` is called without `DK`  along with the comment "relalculate the 
        !!  projection operators (the array was used as a workspace)." `SPHER` is what is
        !!  used to calculate the real projectors without the complex phase.
        !!
        !!  Based on this comment, I am going to assume that `DK` isn't present, which means
        !!  that this section in the original `SPHER` subroutine is skipped. 
        !! @endnote
    enddo
  
    return
  end subroutine generateGridTable

!----------------------------------------------------------------------------
  function maxL(nAtomTypes, pot)
    !! Get the maximum L quantum number across all
    !! pseudopotentials

    implicit none

    ! Input variables:
    integer, intent(in) :: nAtomTypes
      !! Number of types of atoms

    type (potcar) :: pot(nAtomTypes)
      !! Holds all information needed from POTCAR

    ! Output variables:
    integer :: maxL
      !! The maximum L quantum number across all 
      !! pseudopotentials

    ! Local variables
    integer :: maxLTmp
      !! Max L in all channels of single atom type
    integer :: iT, ip
      !! Loop indices

    maxL = 0

    do iT = 1, nAtomTypes
      maxLTmp = 0

      do ip = 1, pot(iT)%nChannels
            
        maxLTmp = max(pot(iT)%angMom(ip), maxLTmp)

      enddo

      maxL = max(maxL, maxLTmp)
      
    enddo

  end function maxL

!----------------------------------------------------------------------------
  subroutine getYlm(nGkVecsLocal_ik, YDimL, YDimLM, gkUnit, Ylm)
    implicit none

    ! Input variables:
    integer, intent(in) :: nGkVecsLocal_ik
      !! Local number of G-vectors on this processor
      !! for a given k-point
    integer, intent(in) :: YDimL
      !! L dimension of spherical harmonics;
      !! max l quantum number across all
      !! pseudopotentials
    integer, intent(in) :: YDimLM
      !! Total number of lm combinations

    real(kind=dp), intent(in) :: gkUnit(3,nGkVecsLocal_ik)
      !! \( (G+k)/|G+k| \)

    ! Output variables:
    real(kind=dp), intent(out) :: Ylm(nGkVecsLocal_ik,YDimLM)
      !! Spherical harmonics

    ! Local variables:
    integer :: ipw
      !! Loop index

    real(kind=dp) :: multFact
      !! Factor that is multiplied in front
      !! of all spherical harmonics
    real(kind=dp) :: multFactTmp
      !! Multiplication factor for a specific
      !! calculation


    if(YDimL < 0) return
      !! Return if there is no angular momentum dimension.
      !! This shouldn't happen, but a check just in case

    Ylm(:,:) = 0._dp
      !! Initialize all spherical harmonics to zero

    multFact = 1/(2._dp*sqrt(pi))
      !! Set factor that is in front of all spherical
      !! harmonics

    Ylm(:,1) = multFact
      !! Directly calculate L=0 case

    if(YDimL < 1) return
      !! Return if the max L quantum number is 0

    !> Directly calculate L=1 case
    multFactTmp = multFact*sqrt(3._dp)
    do ipw = 1, nGkVecsLocal_ik

      Ylm(ipw,2)  = multFactTmp*gkUnit(2,ipw)
      Ylm(ipw,3)  = multFactTmp*gkUnit(3,ipw)
      Ylm(ipw,4)  = multFactTmp*gkUnit(1,ipw)

    enddo

    if(YDimL < 2) return
      !! Return if the max L quantum number is 1

    !> Directly calculate L=2 case
    multFactTmp = multFact*sqrt(15._dp)
    do ipw = 1, nGkVecsLocal_ik

        Ylm(ipw,5)= multFactTmp*gkUnit(1,ipw)*gkUnit(2,ipw)
        Ylm(ipw,6)= multFactTmp*gkUnit(2,ipw)*gkUnit(3,ipw)
        Ylm(ipw,7)= (multFact*sqrt(5._dp)/2._dp)*(3._dp*gkUnit(3,ipw)*gkUnit(3,ipw) - 1)
        Ylm(ipw,8)= multFactTmp*gkUnit(1,ipw)*gkUnit(3,ipw)
        Ylm(ipw,9)= (multFactTmp/2._dp)*(gkUnit(1,ipw)*gkUnit(1,ipw) - gkUnit(2,ipw)*gkUnit(2,ipw))

    enddo

    if(YDimL < 3) return
      !! Return if the max L quantum number is 2


    call exitError('getYlm', &
        '*** error - expected YDimL < 3', 1)
      !> @note
      !>  This code only considers up to d electrons! The spherical
      !>  harmonics are much more complicated to calculate past that 
      !>  point, but we have no use for it right now, so I am just 
      !>  going to skip it. 
      !> @endnote


    return
  end subroutine getYlm

!----------------------------------------------------------------------------
  subroutine getPseudoV(ip, nGkVecsLocal_ik, gkMod, multFact, omega, pot, pseudoV)
    implicit none

    ! Input variables:
    integer, intent(in) :: ip
      !! Channel index
    integer, intent(in) :: nGkVecsLocal_ik
      !! Local number of G-vectors on this processor
      !! for a given k-point

    real(kind=dp), intent(in) :: gkMod(nGkVecsLocal_ik)
      !! \(|G+k|^2\)
    real(kind=dp), intent(in) :: multFact(nGkVecsLocal_ik)
      !! Multiplicative factor for the pseudopotential;
      !! only used in the Gamma-only version
    real(kind=dp), intent(in) :: omega
      !! Volume of unit cell

    type (potcar) :: pot
      !! Holds all information needed from POTCAR
      !! for the specific atom type considered

    ! Output variables:
    real(kind=dp), allocatable, intent(out) :: pseudoV(:)
      !! Pseudopotential

    ! Local variables:
    integer :: iPsGr
      !! Index on pseudopotential grid
    integer :: ipw
      !! Loop index

    real(kind=dp) :: a_ipw, b_ipw, c_ipw, d_ipw
      !! Cubic spline coefficients for recreating
      !! pseudopotential
    real(kind=dp) :: GkLenToPseudoGrid
      !! Factor to scale from \(G+k\) length scale
      !! to non-linear grid of size `nonlPseudoGridSize`
    real(kind=dp) :: divSqrtOmega
      !! 1/sqrt(omega) for multiplying pseudopotential
    real(kind=dp) :: pseudoGridLoc
      !! Location of \(G+k\) vector on pseudopotential 
      !! grid, scaled by the \(|G+k|\)
    real(kind=dp) :: rem
      !! Decimal part of `pseudoGridLoc`, used for recreating
      !! pseudopotential from cubic spline interpolation
    real(kind=dp) :: rp1, rp2, rp3, rp4
      !! Compressed recipocal-space projectors as read from
      !! the POTCAR file


    allocate(pseudoV(nGkVecsLocal_ik))

    divSqrtOmega = 1/sqrt(omega/angToBohr**3)

    GkLenToPseudoGrid = nonlPseudoGridSize/pot%maxGkNonlPs
      !! * Define a scale factor for the argument based on the
      !!   length of the G-vector. Convert from continous G-vector
      !!   length scale to discrete scale of size `nonlPseudoGridSize`.

    do ipw = 1, nGkVecsLocal_ik

      pseudoGridLoc = gkMod(ipw)*GkLenToPseudoGrid + 1
        !! * Get a location of this \(G+k\) vector scaled to
        !!   the size of the non-linear pseudopotential grid.
        !!   This value is real.

      iPsGr = int(pseudoGridLoc)
        !! * Get the integer part of the location, which will be 
        !!   used to index the reciprocal-space projectors as read
        !!   in from the POTCAR file

      rem = mod(pseudoGridLoc,1.0_dp)
        !! * Get the remainder, which is used for recreating the
        !!   pseudopotential from a cubic spline interpolation

      pseudoV(ipw) = 0._dp

      !IF (ASSOCIATED(P(NT)%PSPNL_SPLINE)) THEN
        !! @note
        !!  Default `NLSPLINE = .FALSE.`, which is recommended except for specific
        !!  applications not relevant to our purposes, so this section in the original
        !!  `SPHER` subroutine is skipped.
        !! @endnote

      rp1 = pot%recipProj(ip, iPsGr-1)
      rp2 = pot%recipProj(ip, iPsGr)
      rp3 = pot%recipProj(ip, iPsGr+1)
      rp4 = pot%recipProj(ip, iPsGr+2)

      a_ipw = rp2
      b_ipw = (6*rp3 - 2*rp1 - 3*rp2 - rp4)/6._dp
      c_ipw = (rp1 + rp3 - 2*rp2)/2._dp
      d_ipw = (rp4 - rp1 + 3*(rp2 - rp3))/6._dp
        !! * Decode the spline coefficients from the compressed reciprocal
        !!   projectors read from the POTCAR file

      pseudoV(ipw) = (a_ipw + rem*(b_ipw + rem*(c_ipw + rem*d_ipw)))*divSqrtOmega*multFact(ipw)
        !! * Recreate full pseudopotential from cubic spline coefficients:
        !!   \( \text{pseudo} = a_i + dx\cdot b_i + dx^2\cdot c_i + dx^3\cdot d_i \)
        !!   where the \(i\) index is the plane-wave index, and \(dx\) is the decimal
        !!   part of the pseudopotential-grid location

      !IF (VPS(IND) /= 0._dp .AND. PRESENT(DK)) THEN
        !! @note
        !!  At the end of the subroutine `STRENL` in `nonl.F` that calculates the forces,
        !!  `SPHER` is called without `DK`  along with the comment "relalculate the 
        !!  projection operators (the array was used as a workspace)." `SPHER` is what is
        !!  used to calculate the real projectors without the complex phase.
        !!
        !!  Based on this comment, I am going to assume that `DK` isn't present, which means
        !!  that this section in the original `SPHER` subroutine is skipped. 
        !! @endnote
    enddo

    return
  end subroutine getPseudoV

!----------------------------------------------------------------------------
  subroutine writeProjectors(ik, nAtoms, iType, maxNumPWsGlobal, nAtomTypes, nAtomsEachType, nGkVecsLocal_ik, nKPoints, nPWs1k, &
        gKSort, realProjWoPhase, compFact, phaseExp, exportDir, pot)

    use miscUtilities, only: int2str

    implicit none

    ! Input variables:
    integer, intent(in) :: ik
      !! Current k-point
    integer, intent(in) :: nAtoms
      !! Number of atoms
    integer, intent(in) :: iType(nAtoms)
      !! Atom type index
    integer, intent(in) :: maxNumPWsGlobal
      !! Max number of \(G+k\) vectors with magnitude
      !! less than `wfcVecCut` among all k-points
    integer, intent(in) :: nAtomTypes
      !! Number of types of atoms
    integer, intent(in) :: nAtomsEachType(nAtomTypes)
      !! Number of atoms of each type
    integer, intent(in) :: nGkVecsLocal_ik
      !! Local number of G-vectors on this processor
      !! for a given k-point
    integer, intent(in) :: nKPoints
      !! Total number of k-points
    integer, intent(in) :: nPWs1k
      !! Input number of plane waves for the given k-point
    integer, intent(in) :: gKSort(maxNumPWsGlobal, nKPoints)
      !! Indices to recover sorted order on reduced
      !! \(G+k\) grid

    real(kind=dp), intent(in) :: realProjWoPhase(nGkVecsLocal_ik,64,nAtomTypes)
      !! Real projectors without phase

    complex(kind=dp), intent(in) :: compFact(64,nAtomTypes)
      !! Complex "phase" factor
    complex(kind=dp), intent(in) :: phaseExp(nGkVecsLocal_ik,nAtoms)
      !! Exponential phase factor

    character(len=256), intent(in) :: exportDir
      !! Directory to be used for export

    type (potcar) :: pot(nAtomTypes)
      !! Holds all information needed from POTCAR

    ! Local variables:
    integer :: nProj
      !! Number of projectors across all atom types
    integer :: projOutUnit
      !! Process-dependent file unit for `projectors.ik`
    integer :: sendCount(nProcPerPool)
      !! Number of items to send to each process
      !! in the pool
    integer :: displacement(nProcPerPool)
      !! Offset from beginning of array for
      !! scattering coefficients to each process
    integer :: iT, ia, ilm, ipw, ikGlobal
      !! Loop indices

    real(kind=dp) :: realProjWoPhaseGlobal(nPWs1k,64,nAtomTypes)
      !! Real projectors without phase

    complex(kind=dp) :: phaseExpGlobal(nPWs1k, nAtoms)
      !! Exponential phase factor

    character(len=300) :: ikC
      !! Character index


    if(indexInPool == 1) then
      ! Have process 1 handle projectors output and
      ! process 0 handle wfc output

      ikGlobal = ik+ikStart_pool-1

      call int2str(ikGlobal, ikC)

      projOutUnit = 83 + myid
      open(projOutUnit, file=trim(exportDir)//"/projectors."//trim(ikC))
        ! Open `projectors.ik` file

      write(projOutUnit, '("# Complex projectors |beta>. Format: ''(2ES24.15E3)''")')
        !! Write header for projectors file

      nProj = 0
      do iT = 1, nAtomTypes
        !! Calculate the total number of projectors across all
        !! atom types

        nProj = nProj + pot(iT)%lmmax*nAtomsEachType(iT)

      enddo

      write(projOutUnit,'(2i10)') nProj, nPWs1k
        !! Write out the number of projectors and number of
        !! \(G+k\) vectors at this k-point below the energy
        !! cutoff

    endif

    sendCount = 0
    sendCount(indexInPool+1) = nGkVecsLocal_ik
    call mpiSumIntV(sendCount, intraPoolComm)
      !! * Put the number of G+k vectors on each process
      !!   in a single array per pool

    displacement = 0
    displacement(indexInPool+1) = iGkStart_pool(ik)-1
    call mpiSumIntV(displacement, intraPoolComm)
      !! * Put the displacement from the beginning of the array
      !!   for each process in a single array per pool

    do ia = 1, nAtoms
      !! * Gather data to process 1 for outputting

      iT = iType(ia)
        !! Store the index of the type for this atom

      call MPI_GATHERV(phaseExp(1:nGkVecsLocal_ik,ia), nGkVecsLocal_ik, MPI_DOUBLE_COMPLEX, phaseExpGlobal(:,ia), sendCount, &
          displacement, MPI_DOUBLE_COMPLEX, 1, intraPoolComm, ierr)

      do ilm = 1, pot(iT)%lmmax

        call MPI_GATHERV(realProjWoPhase(1:nGkVecsLocal_ik,ilm,iT), nGkVecsLocal_ik, MPI_DOUBLE_PRECISION, realProjWoPhaseGlobal(:,ilm,iT), &
            sendCount, displacement, MPI_DOUBLE_PRECISION, 1, intraPoolComm, ierr)

      enddo

    enddo

    if(indexInPool == 1) then
      !! Write out data from process 1

      do ia = 1, nAtoms
    
        iT = iType(ia)
          !! Store the index of the type for this atom

        do ilm = 1, pot(iT)%lmmax

          do ipw = 1, nPWs1k
            !! Calculate \(|\beta\rangle\)

            write(projOutUnit,'(2ES24.15E3)') &
              conjg(realProjWoPhaseGlobal(gKSort(ipw,ikGlobal),ilm,iT)*phaseExpGlobal(gKSort(ipw,ikGlobal),ia)*compFact(ilm,iT))
              !! @note
              !!    The projectors are stored as \(\langle\beta|\), so need to take the complex conjugate
              !!    to output \(|\beta\rangle.
              !! @endnote
              !! @note
              !!    The projectors should have units inverse to those of the coefficients. That was
              !!    previously listed as (a.u.)^(-3/2), but the `TME` code seems to expect both the
              !!    projectors and the wave function coefficients to be unitless, so there should be
              !!    no unit conversion here.
              !! @endnote
              !! @note
              !!    `NONL_S%LSPIRAL = .FALSE.`, so spin spirals are not calculated, which makes
              !!    `NONL_S%QPROJ` spin-independent. This is why there is no spin index on `realProjWoPhase`.
              !! @endnote

          enddo
        enddo
      enddo

      close(projOutUnit)
    endif

    return
  end subroutine writeProjectors

!----------------------------------------------------------------------------
  subroutine readAndWriteWavefunction(ik, isp, maxNumPWsGlobal, nBands, nGkVecsLocal_ik, nKPoints, nPWs1k, gKSort, exportDir, irec, coeffLocal)
    !! For each spin and k-point, read and write the plane
    !! wave coefficients for each band
    !!
    !! <h2>Walkthrough</h2>
    !!

    use miscUtilities, only: int2str

    implicit none

    ! Input variables:
    integer, intent(in) :: ik
      !! Current k-point
    integer, intent(in) :: isp
      !! Current spin channel
    integer, intent(in) :: maxNumPWsGlobal
      !! Max number of \(G+k\) vectors with magnitude
      !! less than `wfcVecCut` among all k-points
    integer, intent(in) :: nBands
      !! Total number of bands
    integer, intent(in) :: nGkVecsLocal_ik
      !! Local number of G-vectors on this processor
      !! for a given k-point
    integer, intent(in) :: nKPoints
      !! Total number of k-points
    integer, intent(in) :: nPWs1k
      !! Input number of plane waves for the given k-point
    integer, intent(in) :: gKSort(maxNumPWsGlobal, nKPoints)
      !! Indices to recover sorted order on reduced
      !! \(G+k\) grid
      
    character(len=256), intent(in) :: exportDir
      !! Directory to be used for export

    ! Output variables:
    integer, intent(inout) :: irec

    complex*8, intent(out) :: coeffLocal(nGkVecsLocal_ik, nBands)
      !! Plane wave coefficients

    ! Local variables:
    integer :: sendCount(nProcPerPool)
      !! Number of items to send to each process
      !! in the pool
    integer :: displacement(nProcPerPool)
      !! Offset from beginning of array for
      !! scattering coefficients to each process
    integer :: wfcOutUnit
      !! Process-dependent file unit for `wfc.ik`
    integer :: ib, ipw, iproc
      !! Loop indices

    complex*8, allocatable :: coeff(:,:)
      !! Plane wave coefficients

    character(len=300) :: ikC, ispC
      !! Character index


    if(indexInPool == 0) then
      !! Have the root node within the pool handle I/O

      allocate(coeff(maxNumPWsGlobal, nBands))

      wfcOutUnit = 83 + myid

      call int2str(ik+ikStart_pool-1, ikC)
      call int2str(isp, ispC)

      open(wfcOutUnit, file=trim(exportDir)//"/wfc."//trim(ispC)//"."//trim(ikC))
        ! Open `wfc.ik` file to write plane wave coefficients

      write(wfcOutUnit, '("# Spin : ",i10, " Format: ''(a9, i10)''")') isp
      write(wfcOutUnit, '("# Complex : wavefunction coefficients. Format: ''(2ES24.15E3)''")')
        ! Write header to `wfc.isp.ik` file

      do ib = 1, nBands

        irec = irec + 1

        read(unit=wavecarUnit,rec=irec) (coeff(ipw,ib), ipw=1,nPWs1k)
          ! Read in the plane wave coefficients for each band

        do ipw = 1, nPWs1k

          write(wfcOutUnit,'(2ES24.15E3)') coeff(gKSort(ipw,ik+ikStart_pool-1),ib)
            ! Write out in sorted order
            !! @note
            !!  I was trying to convert these coefficients based
            !!  on the units previously listed in the `wfc.ik` file, 
            !!  but I don't think those are accurate. Based on the 
            !!  `TME` code, it seems like these coefficients are 
            !!  actually treated as unitless, so there should be no 
            !!  unit conversion here.
            !! @endnote

        enddo

      enddo

      close(wfcOutUnit)
        ! Close `wfc.ik` file

    endif

    sendCount = 0
    sendCount(indexInPool+1) = nGkVecsLocal_ik
    call mpiSumIntV(sendCount, intraPoolComm)
      !! * Put the number of G+k vectors on each process
      !!   in a single array per pool

    displacement = 0
    displacement(indexInPool+1) = iGkStart_pool(ik)-1
    call mpiSumIntV(displacement, intraPoolComm)
      !! * Put the displacement from the beginning of the array
      !!   for each process in a single array per pool

    do ib = 1, nBands
      !! * For each band, scatter the coefficients across all 
      !!   of the processes in the pool

      call MPI_SCATTERV(coeff(:,ib), sendCount, displacement, MPI_COMPLEX, coeffLocal(1:nGkVecsLocal_ik,ib), nGkVecsLocal_ik, &
          MPI_COMPLEX, 0, intraPoolComm, ierr)

    enddo

    if(indexInPool == 0) deallocate(coeff)

    return
  end subroutine readAndWriteWavefunction

!----------------------------------------------------------------------------
  subroutine getAndWriteProjections(ik, isp, nAtoms, nAtomTypes, nAtomsEachType, nBands, nGkVecsLocal_ik, nKPoints, realProjWoPhase, compFact, &
          phaseExp, coeffLocal, exportDir, pot)

    use miscUtilities, only: int2str

    implicit none

    ! Input variables:
    integer, intent(in) :: ik
      !! Current k-point
    integer, intent(in) :: isp
      !! Current spin channel
    integer, intent(in) :: nAtoms
      !! Number of atoms
    integer, intent(in) :: nAtomTypes
      !! Number of types of atoms
    integer, intent(in) :: nAtomsEachType(nAtomTypes)
      !! Number of atoms of each type
    integer, intent(in) :: nBands
      !! Total number of bands
    integer, intent(in) :: nGkVecsLocal_ik
      !! Local number of G-vectors on this processor
      !! for a given k-point
    integer, intent(in) :: nKPoints
      !! Total number of k-points

    real(kind=dp), intent(in) :: realProjWoPhase(nGkVecsLocal_ik,64,nAtomTypes)
      !! Real projectors without phase

    complex(kind=dp), intent(in) :: compFact(64,nAtomTypes)
      !! Complex "phase" factor
    complex(kind=dp), intent(in) :: phaseExp(nGkVecsLocal_ik,nAtoms)

    complex*8, intent(in) :: coeffLocal(nGkVecsLocal_ik, nBands)
      !! Plane wave coefficients
      
    character(len=256), intent(in) :: exportDir
      !! Directory to be used for export

    type (potcar) :: pot(nAtomTypes)
      !! Holds all information needed from POTCAR

    ! Local variables:
    integer :: ionode_k_id
      !! ID for the node that outputs for this k-point
    integer :: projOutUnit
      !! Process-dependent file unit for `projections.ik`
    integer :: ib, iT, ia, iaBase, ilm
      !! Loop indices

    character(len=300) :: ikC, ispC
      !! Character index

    complex*8 :: projection, projectionLocal
      !! Projection for current atom/band/lm channel


    if(indexInPool == 0) then
      !! Have the root node within the pool handle I/O

      projOutUnit = 83 + myid

      call int2str(ik, ikC)
      call int2str(isp, ispC)

      open(projOutUnit, file=trim(exportDir)//"/projections."//trim(ispC)//"."//trim(ikC))
        !! Open `projections.ik`

      write(projOutUnit, '("# Complex projections <beta|psi>. Format: ''(2ES24.15E3)''")')

    endif

    do ib = 1, nBands
      iaBase = 1
      
      do iT = 1, nAtomTypes
        do ia = iaBase, nAtomsEachType(iT)+iaBase-1
          do ilm = 1, pot(iT)%lmmax

            projectionLocal = compFact(ilm,iT)*sum(realProjWoPhase(:,ilm,iT)*phaseExp(:,ia)*coeffLocal(:,ib))
              ! Calculate projection (sum over plane waves)
              ! Don't need to worry about sorting because projection
              ! has sum over plane waves.

            call MPI_REDUCE(projectionLocal, projection, 1, MPI_COMPLEX, MPI_SUM, root, intraPoolComm, ierr)

            if(indexInPool == 0) write(projOutUnit,'(2ES24.15E3)') projection

          enddo
        enddo
      enddo
    enddo

    if(indexInPool == 0) close(projOutUnit)

    return
  end subroutine getAndWriteProjections

!----------------------------------------------------------------------------
  subroutine writeKInfo(nBands, nKPoints, nGkLessECutGlobal, nSpins, bandOccupation, kWeight, kPosition)
    !! Calculate the highest occupied band for each k-point
    !! and write out k-point information
    !!
    !! <h2>Walkthrough</h2>
    !!

    implicit none

    ! Input variables:
    integer, intent(in) :: nBands
      !! Total number of bands
    integer, intent(in) :: nKPoints
      !! Total number of k-points
    integer, intent(in) :: nGkLessECutGlobal(nKPoints)
      !! Global number of \(G+k\) vectors with magnitude
      !! less than `wfcVecCut` for each k-point
    integer, intent(in) :: nSpins
      !! Number of spins

    real(kind=dp), intent(in) :: bandOccupation(nSpins, nBands, nKPoints)
      !! Occupation of band
    real(kind=dp), intent(in) :: kWeight(nKPoints)
      !! K-point weights
    real(kind=dp), intent(in) :: kPosition(3,nKPoints)
      !! Position of k-points in reciprocal space


    ! Output variables:


    ! Local variables:
    integer, allocatable :: groundState(:,:)
      !! Holds the highest occupied band
      !! for each k-point and spin
    integer :: ik, isp
      !! Loop indices


    if(ionode) then

      write(iostd,*)
      write(iostd,*) "***************"
      write(iostd,*) "Getting ground state bands"
    
      allocate(groundState(nSpins,nKPoints))

      call getGroundState(nBands, nKPoints, nSpins, bandOccupation, groundState)
        !! * For each k-point, find the index of the 
        !!   highest occupied band
        !!
        !! @note
        !!  Although `groundState` is written out in `Export`,
        !!  it is not currently used by the `TME` program.
        !! @endnote

      open(72, file=trim(exportDir)//"/groundState")

      write(72, '("# isp, ik, groundState(isp,ik). Format: ''(3i10)''")')

      do isp = 1, nSpins
        do ik = 1, nKPoints

          write(72, '(3i10)') isp, ik, groundState(isp,ik)

        enddo
      enddo

      close(72)

      deallocate(groundState)
          

      write(iostd,*) "Done getting ground state bands"
      write(iostd,*) "***************"
      write(iostd,*)

      write(iostd,*)
      write(iostd,*) "***************"
      write(iostd,*) "Writing out k info"
    
      write(mainOutFileUnit, '("# Number of spins. Format: ''(i10)''")')
      write(mainOutFileUnit, '(i10)') nSpins

      write(mainOutFileUnit, '("# Number of K-points. Format: ''(i10)''")')
      write(mainOutFileUnit, '(i10)') nKPoints

      write(mainOutFileUnit, '("# ik, nGkLessECutGlobal(ik), wk(ik), xk(1:3,ik). Format: ''(2i10,4ES24.15E3)''")')
      flush(mainOutFileUnit)

      do ik = 1, nKPoints
    
        write(mainOutFileUnit, '(2i10,4ES24.15E3)') ik, nGkLessECutGlobal(ik), kWeight(ik), kPosition(1:3,ik)
        flush(mainOutFileUnit)
          !! * Write the k-point index, the number of G-vectors, 
          !!   weight, and position for this k-point

      enddo

      write(iostd,*) "Done writing out k info"
      write(iostd,*) "***************"
      write(iostd,*)
      flush(iostd)

    endif

    return
  end subroutine writeKInfo

!----------------------------------------------------------------------------
  subroutine getGroundState(nBands, nKPoints, nSpins, bandOccupation, groundState)
    !! * For each k-point, find the index of the 
    !!   highest occupied band

    implicit none

    ! Input variables:
    integer, intent(in) :: nBands
      !! Total number of bands
    integer, intent(in) :: nKPoints
      !! Total number of k-points
    integer, intent(in) :: nSpins
      !! Number of spins

    real(kind=dp), intent(in) :: bandOccupation(nSpins, nBands, nKPoints)
      !! Occupation of band

    
    ! Output variables:
    integer, intent(out) :: groundState(nSpins, nKPoints)
      !! Holds the highest occupied band
      !! for each k-point and spin


    ! Local variables:
    integer :: ik, ibnd, isp
      !! Loop indices


    groundState(:,:) = 0
    do isp = 1, nSpins
      do ik = 1, nKPoints

        do ibnd = 1, nBands

          if (bandOccupation(isp,ibnd,ik) < 0.5_dp) then
            !! @todo Figure out if boundary for "occupied" should be 0.5 or less @endtodo
          !if (et(ibnd,ik) > ef) then

            groundState(isp,ik) = ibnd - 1
            goto 10

          endif
        enddo

10      continue

      enddo
    enddo

    return
  end subroutine getGroundState

!----------------------------------------------------------------------------
  subroutine writeGridInfo(nGVecsGlobal, nKPoints, nSpins, maxNumPWsGlobal, gKIndexGlobal, gVecMillerIndicesGlobal, nGkLessECutGlobal, maxGIndexGlobal, exportDir)
    !! Write out grid boundaries and miller indices
    !! for just \(G+k\) combinations below cutoff energy
    !! in one file and all miller indices in another 
    !! file
    !!
    !! <h2>Walkthrough</h2>
    !!

    use miscUtilities, only: int2str

    implicit none

    ! Input variables:
    integer, intent(in) :: nGVecsGlobal
      !! Global number of G-vectors
    integer, intent(in) :: nKPoints
      !! Total number of k-points
    integer, intent(in) :: nSpins
      !! Number of spins
    integer, intent(in) :: maxNumPWsGlobal
      !! Max number of \(G+k\) vectors with magnitude
      !! less than `wfcVecCut` among all k-points

    integer, intent(in) :: gKIndexGlobal(maxNumPWsGlobal, nKPoints)
      !! Indices of \(G+k\) vectors for each k-point
      !! and all processors
    integer, intent(in) :: gVecMillerIndicesGlobal(3,nGVecsGlobal)
      !! Integer coefficients for G-vectors on all processors
    integer, intent(in) :: nGkLessECutGlobal(nKPoints)
      !! Global number of \(G+k\) vectors with magnitude
      !! less than `wfcVecCut` for each k-point
    integer, intent(in) :: maxGIndexGlobal
      !! Maximum G-vector index among all \(G+k\)
      !! and processors

    character(len=256), intent(in) :: exportDir
      !! Directory to be used for export


    ! Output variables:


    ! Local variables:
    integer :: ikLocal, ikGlobal, ig, igk, isp
      !! Loop indices

    character(len=300) :: ikC, ispC
      !! Character index


    if (ionode) then
    
      !> * Write the global number of G-vectors, the maximum
      !>   G-vector index, and the max/min miller indices
      write(mainOutFileUnit, '("# Number of G-vectors. Format: ''(i10)''")')
      write(mainOutFileUnit, '(i10)') nGVecsGlobal
    
      write(mainOutFileUnit, '("# Number of PW-vectors. Format: ''(i10)''")')
      write(mainOutFileUnit, '(i10)') maxGIndexGlobal
    
      write(mainOutFileUnit, '("# Number of min - max values of fft grid in x, y and z axis. Format: ''(6i10)''")')
      write(mainOutFileUnit, '(6i10)') minval(gVecMillerIndicesGlobal(1,1:nGVecsGlobal)), maxval(gVecMillerIndicesGlobal(1,1:nGVecsGlobal)), &
                          minval(gVecMillerIndicesGlobal(2,1:nGVecsGlobal)), maxval(gVecMillerIndicesGlobal(2,1:nGVecsGlobal)), &
                          minval(gVecMillerIndicesGlobal(3,1:nGVecsGlobal)), maxval(gVecMillerIndicesGlobal(3,1:nGVecsGlobal))
      flush(mainOutFileUnit)

    endif
    
    if(indexInPool == 0) then
      do ikLocal = 1, nKPerPool
        !! * For each k-point, write out the miller indices
        !!   resulting in \(G+k\) vectors less than the energy
        !!   cutoff in a `grid.ik` file
      
        ikGlobal = ikLocal+ikStart_pool-1
        call int2str(ikGlobal, ikC)

        open(72, file=trim(exportDir)//"/grid."//trim(ikC))
        write(72, '("# Wave function G-vectors grid")')
        write(72, '("# G-vector index, G-vector(1:3) miller indices. Format: ''(4i10)''")')
      
        do igk = 1, nGkLessECutGlobal(ikGlobal)
          write(72, '(4i10)') gKIndexGlobal(igk,ikGlobal), gVecMillerIndicesGlobal(1:3,gKIndexGlobal(igk,ikGlobal))
          flush(72)
        enddo
      
        close(72)

      enddo

    endif

    if(ionode) then

      !> * Output all miller indices in `mgrid` file
      open(72, file=trim(exportDir)//"/mgrid")
      write(72, '("# Full G-vectors grid")')
      write(72, '("# G-vector index, G-vector(1:3) miller indices. Format: ''(4i10)''")')
    
      do ig = 1, nGVecsGlobal
        write(72, '(4i10)') ig, gVecMillerIndicesGlobal(1:3,ig)
        flush(72)
      enddo
    
      close(72)

    endif

    return
  end subroutine writeGridInfo


!----------------------------------------------------------------------------
  subroutine writeCellInfo(iType, nAtoms, nBands, nAtomTypes, realLattVec, recipLattVec, atomPositionsDir)
    !! Write out the real- and reciprocal-space lattice vectors, 
    !! the number of atoms, the number of types of atoms, the
    !! final atom positions, number of bands, and number of spins

    implicit none

    ! Input variables:
    integer, intent(in) :: nAtoms
      !! Number of atoms
    integer, intent(in) :: iType(nAtoms)
      !! Atom type index
    integer, intent(in) :: nBands
      !! Total number of bands
    integer, intent(in) :: nAtomTypes
      !! Number of types of atoms

    real(kind=dp), intent(in) :: realLattVec(3,3)
      !! Real space lattice vectors
    real(kind=dp), intent(in) :: recipLattVec(3,3)
      !! Reciprocal lattice vectors
    real(kind=dp), intent(in) :: atomPositionsDir(3,nAtoms)
      !! Atom positions

    ! Local variables:
    real(kind=dp) :: atomPositionCart(3)
      !! Position of given atom in cartesian coordinates

    integer :: i, ia, ix
      !! Loop indices


    if (ionode) then
    
      write(mainOutFileUnit, '("# Cell (a.u.). Format: ''(a5, 3ES24.15E3)''")')
      write(mainOutFileUnit, '("# a1 ",3ES24.15E3)') realLattVec(:,1)
      write(mainOutFileUnit, '("# a2 ",3ES24.15E3)') realLattVec(:,2)
      write(mainOutFileUnit, '("# a3 ",3ES24.15E3)') realLattVec(:,3)
    
      write(mainOutFileUnit, '("# Reciprocal cell (a.u.). Format: ''(a5, 3ES24.15E3)''")')
      write(mainOutFileUnit, '("# b1 ",3ES24.15E3)') recipLattVec(:,1)
      write(mainOutFileUnit, '("# b2 ",3ES24.15E3)') recipLattVec(:,2)
      write(mainOutFileUnit, '("# b3 ",3ES24.15E3)') recipLattVec(:,3)
    
      write(mainOutFileUnit, '("# Number of Atoms. Format: ''(i10)''")')
      write(mainOutFileUnit, '(i10)') nAtoms
    
      write(mainOutFileUnit, '("# Number of Types. Format: ''(i10)''")')
      write(mainOutFileUnit, '(i10)') nAtomTypes
    
      write(mainOutFileUnit, '("# Atoms type, position(1:3) (a.u.). Format: ''(i10,3ES24.15E3)''")')

      do ia = 1, nAtoms

        do ix = 1, 3

          atomPositionCart(ix) = sum(atomPositionsDir(:,ia)*realLattVec(ix,:))
            !! @todo Test logic of direct to cartesian coordinates with scaling factor @endtodo

        enddo

        write(mainOutFileUnit,'(i10,3ES24.15E3)') iType(ia), atomPositionCart(:)

      enddo
    
      write(mainOutFileUnit, '("# Number of Bands. Format: ''(i10)''")')
      write(mainOutFileUnit, '(i10)') nBands

    endif

    return
  end subroutine writeCellInfo

!----------------------------------------------------------------------------
  subroutine writePseudoInfo(nAtomTypes, nAtomsEachType, pot)
    !! For each atom type, write out the element name,
    !! number of atoms of this type, projector info,
    !! radial grid info, and partial waves

    implicit none

    ! Input variables:
    integer, intent(in) :: nAtomTypes
      !! Number of types of atoms

    integer, intent(in) :: nAtomsEachType(nAtomTypes)
      !! Number of atoms of each type

    type (potcar) :: pot(nAtomTypes)
      !! Holds all information needed from POTCAR


    ! Output variables:


    ! Local variables:
    integer :: iT, ip, ir
      !! Loop index

  
    if (ionode) then

      do iT = 1, nAtomTypes
        
        write(mainOutFileUnit, '("# Element")')
        write(mainOutFileUnit, *) trim(pot(iT)%element)
        write(mainOutFileUnit, '("# Number of Atoms of this type. Format: ''(i10)''")')
        write(mainOutFileUnit, '(i10)') nAtomsEachType(iT)
        write(mainOutFileUnit, '("# Number of projectors. Format: ''(i10)''")')
        write(mainOutFileUnit, '(i10)') pot(iT)%nChannels
        
        write(mainOutFileUnit, '("# Angular momentum, index of the projectors. Format: ''(2i10)''")')
        do ip = 1, pot(iT)%nChannels

          write(mainOutFileUnit, '(2i10)') pot(iT)%angMom(ip), ip

        enddo
        
        write(mainOutFileUnit, '("# Number of channels. Format: ''(i10)''")')
        write(mainOutFileUnit, '(i10)') pot(iT)%lmmax
        
        write(mainOutFileUnit, '("# Number of radial mesh points. Format: ''(2i10)''")')
        write(mainOutFileUnit, '(2i10)') pot(iT)%nmax, pot(iT)%iRAugMax
          ! Number of points in the radial mesh, number of points inside the aug sphere
        
        write(mainOutFileUnit, '("# Radial grid, Integratable grid. Format: ''(2ES24.15E3)''")')
        do ir = 1, pot(iT)%nmax
          write(mainOutFileUnit, '(2ES24.15E3)') pot(iT)%radGrid(ir), pot(iT)%dRadGrid(ir) 
            ! Radial grid, derivative of radial grid
        enddo
        
        write(mainOutFileUnit, '("# AE, PS radial wfc for each beta function. Format: ''(2ES24.15E3)''")')
        do ip = 1, pot(iT)%nChannels
          do ir = 1, pot(iT)%nmax
            write(mainOutFileUnit, '(2ES24.15E3)') pot(iT)%wae(ir,ip), pot(iT)%wps(ir,ip)
          enddo
        enddo
      
      enddo
    
    endif

    return
  end subroutine writePseudoInfo

!----------------------------------------------------------------------------
  subroutine writeEigenvalues(nBands, nKPoints, nSpins, eFermi, bandOccupation, eigenE)
    !! Write Fermi energy and eigenvalues and occupations for each band

    use miscUtilities

    implicit none

    ! Input variables:
    integer, intent(in) :: nBands
      !! Total number of bands
    integer, intent(in) :: nKPoints
      !! Total number of k-points
    integer, intent(in) :: nSpins
      !! Number of spins
      
    real(kind=dp), intent(in) :: eFermi
      !! Fermi energy
    real(kind=dp), intent(in) :: bandOccupation(nSpins, nBands,nKPoints)
      !! Occupation of band

    complex*16, intent(in) :: eigenE(nSpins,nKPoints,nBands)
      !! Band eigenvalues


    ! Output variables:


    ! Local variables:
    integer :: ik, ib, isp
      !! Loop indices

    character(len=300) :: ikC, ispC
      !! Character index


    if(ionode) then
    
      write(mainOutFileUnit, '("# Fermi Energy (Hartree). Format: ''(ES24.15E3)''")')
      write(mainOutFileUnit, '(ES24.15E3)') eFermi*ryToHartree
      flush(mainOutFileUnit)
    
      do isp = 1, nSpins
        do ik = 1, nKPoints
      
          call int2str(ik, ikC)
          call int2str(isp, ispC)

          open(72, file=trim(exportDir)//"/eigenvalues."//trim(ispC)//"."//trim(ikC))
      
          write(72, '("# Spin : ",i10, " Format: ''(a9, i10)''")') isp
          write(72, '("# Eigenvalues (Hartree), band occupation number. Format: ''(2ES24.15E3)''")')
      
          do ib = 1, nBands

            write(72, '(2ES24.15E3)') real(eigenE(isp,ik,ib))*ryToHartree, bandOccupation(isp,ib,ik)
            flush(72)

          enddo
      
          close(72)
      
        enddo

      enddo
    
    endif

    return
  end subroutine writeEigenvalues

!----------------------------------------------------------------------------
  subroutine subroutineTemplate()
    implicit none


    return
  end subroutine subroutineTemplate

end module wfcExportVASPMod