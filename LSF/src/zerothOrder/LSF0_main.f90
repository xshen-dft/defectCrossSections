program LSF0main
  use LSF0mod

  implicit none

  ! Local variables:
  real(kind=dp) :: timerStart, timerEnd, timer1, timer2
    !! Timers


  call cpu_time(timerStart)

  call mpiInitialization()


  if(ionode) write(*, '("Reading inputs: [ ] Paramters  [ ] Sj  [ ] dE  [ ] Matrix elements")')
  call cpu_time(timer1)

  call readInputParams(iBandIinit, iBandIfinal, iBandFinit, iBandFfinal, order, beta, dt, gamma0, hbarGamma, maxTime, &
        smearingExpTolerance, temperature, EInput, M0Input, outputDir, SjInput)


  call cpu_time(timer2)
  if(ionode) write(*, '("Reading inputs: [X] Paramters  [ ] Sj  [ ] dE  [ ] Matrix elements (",f10.2," secs)")') timer2-timer1
  call cpu_time(timer1)

  call readSj(iBandIinit, iBandIfinal, iBandFinit, iBandFfinal, SjInput, nModes, modeFreq, Sj)


  call cpu_time(timer2)
  if(ionode) write(*, '("Reading inputs: [X] Paramters  [X] Sj  [ ] dE  [ ] Matrix elements (",f10.2," secs)")') timer2-timer1
  call cpu_time(timer1)

  call readEnergy(iBandIinit, iBandIfinal, iBandFinit, iBandFfinal, EInput, dEDelta, dEPlot)


  call cpu_time(timer2)
  if(ionode) write(*, '("Reading inputs: [X] Paramters  [X] Sj  [X] dE  [ ] Matrix elements (",f10.2," secs)")') timer2-timer1
  call cpu_time(timer1)

  call readMatrixElements(iBandIinit, iBandIfinal, iBandFinit, iBandFfinal, M0Input, matrixElement)

  call cpu_time(timer2)
  if(ionode) write(*, '("Reading inputs: [X] Paramters  [X] Sj  [X] dE  [X] Matrix elements (",f10.2," secs)")') timer2-timer1
  call cpu_time(timer1)


  nStepsLocal = ceiling((maxTime/dt)/nProcs)
    ! Would normally calculate the total number of steps as
    !         nSteps = ceiling(maxTime/dt)
    ! then divide the steps across all of the processes. 
    ! However, the number of steps could be a very large
    ! integer that could cause overflow. Instead, directly
    ! calculate the number of steps that each process should 
    ! calculate. If you still get integer overflow, try 
    ! increasing the number of processes. 
    !
    ! Calculating the number of steps for each process
    ! this way will overestimate the number of steps
    ! needed, but that is okay.

  if(mod(nStepsLocal,2) /= 0) nStepsLocal = nStepsLocal + 1
    ! Simpson's method requires the number of integration
    ! steps to be even
   
  if(ionode) write(*,'("Each process is completing ", i15, " time steps.")') nStepsLocal

  iTime_start = myid*nStepsLocal + 1
  iTime_end = (myid + 1)*nStepsLocal


  call getAndWriteTransitionRate(iBandIinit, iBandIfinal, iBandFinit, iBandFfinal, dEDelta, dEPlot, gamma0, matrixElement, temperature)

  
  deallocate(dEDelta)
  deallocate(dEPlot)
  deallocate(matrixElement)
  deallocate(modeFreq)
  deallocate(Sj)


  call MPI_Barrier(worldComm, ierr)
 
  call cpu_time(timerEnd)
  if(ionode) write(*,'("************ LSF complete! (",f10.2," secs) ************")') timerEnd-timerStart

  call MPI_FINALIZE(ierr)

end program LSF0main

