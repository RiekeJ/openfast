module FVW_SUBS

   use NWTC_LIBRARY
   use FVW_TYPES
   use FVW_VortexTools
   use FVW_BiotSavart

   implicit none

   ! --- Module parameters
   ! Circulation solving methods
   integer(IntKi), parameter :: idCircPolarData     = 0
   integer(IntKi), parameter :: idCircNoFlowThrough = 1
   integer(IntKi), parameter :: idCircPrescribed    = 2
   ! Polar data
   integer(IntKi), parameter :: idPolarAeroDyn      = 0
   integer(IntKi), parameter :: idPolar2PiAlpha     = 1
   integer(IntKi), parameter :: idPolar2PiSinAlpha  = 2
   ! Integration method
   integer(IntKi), parameter :: idRK4      = 1 
   integer(IntKi), parameter :: idAB4      = 2
   integer(IntKi), parameter :: idABM4     = 3
   integer(IntKi), parameter :: idEuler1   = 5

   ! Implementation 
   integer(IntKi), parameter :: iNWStart=2 !< Index in r%NW where the near wake start (if >1 then the Wing panels are included in r_NW)
contains

!==========================================================================
!> Helper function for 1d interpolation (interp1d)
function interpolation_array( xvals, yvals, xi, nOut, nIn )
   integer nOut, nIn, arindx, ilo
   real(ReKi), dimension( nOut ) :: interpolation_array, xi
   real(ReKi), dimension( nIn ) :: xvals, yvals, tmp2, tmp3
   real(ReKi)                         :: tmp1
   ilo = 1
   DO arindx = 1, nOut
      IF ( xi( arindx ) .LT. xvals( 1 )) THEN
         interpolation_array( arindx ) = yvals( 1 ) + ( xi( arindx ) - xvals( 1 )) / &
            & ( xvals( 2 ) - xvals( 1 )) * ( yvals( 2 ) - yvals( 1 ))
      ELSE IF ( xi( arindx ) .GT. xvals( nIn )) THEN
         interpolation_array( arindx ) = yvals( nIn - 1 ) + ( xi( arindx ) - &
            & xvals( nIn - 1 )) / ( xvals( nIn ) - xvals( nIn - 1 )) * &
            & ( yvals( nIn ) - yvals( nIn - 1 ))
      ELSE
         tmp1 = real( xi( arindx ), ReKi)
         tmp2 = real( xvals , ReKi)
         tmp3 = real( yvals , ReKi)
         interpolation_array( arindx ) = InterpBinReal( tmp1, tmp2, tmp3, ilo, nIn )
      END IF
   END DO
END FUNCTION interpolation_array
!==========================================================================

! =====================================================================================
!> Output blade circulation 
subroutine Output_Gamma(CP, Gamma_LL, iWing, iCall, Time)
   real( ReKi ), dimension( :, : ), intent(in   ) :: CP       !< Control Points
   real( ReKi ), dimension( : ),    intent(in   ) :: Gamma_LL !< Circulation on the lifting line
   integer( IntKi ),                intent(in   ) :: iWing    !< Wing index
   integer( IntKi ),                intent(in   ) :: iCall    !< Call ID
   real(DbKi),                      intent(in   ) :: Time
   character(len=255) :: filename
   integer :: i
   integer :: iUnit
   real(ReKi) :: norm
   call GetNewUnit(iUnit)
   ! TODO output folder
   write(filename,'(A,I0,A,I0,A,I0,A)')'Gamma/Gamma_call',int(iCall),'_t',int(Time*10000),'_Wing',int(iWing),'.txt'
   OPEN(unit = iUnit, file = trim(filename), status="unknown", action="write")
   write(iUnit,'(A)') 'norm_[m],x_[m],y_[m],z_[m], Gamma_[m^2/s]'
   do i=1,size(Gamma_LL)
      norm=sqrt(CP(1,i)**2+CP(2,i)**2+CP(3,i)**2)
      write(iUnit,'(E14.7,A,E14.7,A,E14.7,A,E14.7,A,E14.7)') norm,',', CP(1,i),',',CP(2,i),',',CP(3,i),',', Gamma_LL(i)
   enddo
   close(iUnit)
endsubroutine Output_Gamma
! =====================================================================================
!> Read a delimited file  containing a circulation and interpolate it on the requested Control Points
!! The input file is a delimited file with one line of header. 
!! Each following line consists of two columns: r/R_[-] and Gamma_[m^2/s]
subroutine ReadAndInterpGamma(CirculationFileName, s_CP_LL, L, Gamma_CP_LL)
   character(len=*),           intent(in   ) :: CirculationFileName !< Input file to read
   real(ReKi), dimension(:),   intent(in   ) :: s_CP_LL             !< Spanwise location of the lifting CP [m]
   real(ReKi),                 intent(in   ) :: L                   !< Full span of lifting line
   real(ReKi), dimension(:),   intent(out  ) :: Gamma_CP_LL         !< Interpolated circulation of the LL CP
   ! Local
   integer(IntKi)      :: nLines
   integer(IntKi)      :: i
   integer(IntKi)      :: iStat
   integer(IntKi)      :: nr
   integer(IntKi)      :: iUnit
   character(len=1054) :: line
   real(ReKi), dimension(:), allocatable :: sPrescr, GammaPrescr !< Radius
   ! --- 
   call GetNewUnit(iUnit)
   open(unit = iUnit, file = CirculationFileName)
   nLines=line_count(iUnit)-1
   ! Read Header
   read(iUnit,*, iostat=istat) line 
   ! Read table:  s/L [-], GammaPresc [m^2/s]
   allocate(sPrescr(1:nLines), GammaPrescr(1:nLines))
   do i=1,nLines
      read(iUnit,*, iostat=istat) sPrescr(i), GammaPrescr(i)
      sPrescr(i)     =   sPrescr(i) * L
      GammaPrescr(i) =   GammaPrescr(i) 
   enddo
   close(iUnit)
   if (istat/=0) then
      print*,'Error occured while reading Circulation file'
      STOP
   endif
   ! NOTE: TODO TODO TODO THIS ROUTINE PERFORMS NASTY EXTRAPOLATION, SHOULD BE PLATEAUED
   Gamma_CP_LL =  interpolation_array( sPrescr, GammaPrescr, s_CP_LL, size(s_CP_LL), nLines )
contains

   !> Counts number of lines in a file
   integer function line_count(iunit)
      integer(IntKi), intent(in) :: iunit
      character(len=1054) :: line
      ! safety for infinite loop..
      integer(IntKi), parameter :: nline_max=100000000 ! 100 M
      integer(IntKi) :: i
      line_count=0
      do i=1,nline_max 
         line=''
         read(iunit,'(A)',END=100)line
         line_count=line_count+1
      enddo
      if (line_count==nline_max) then
         print*,'Error: MainIO: maximum number of line exceeded'
         STOP
      endif
      100 if(len(trim(line))>0) then
         line_count=line_count+1
      endif
      rewind(iunit)
   end function

endsubroutine ReadAndInterpGamma
! =====================================================================================
!> Prescribe circulation on the blade (based on an input file for now...)
subroutine Prescribe_Gamma( Gamma_LL)
   real( ReKi ), dimension( : ),   intent(out  ) :: Gamma_LL    !< Circulation on the lifting line
   integer :: i
   integer :: iUnit
   integer :: nr
   integer :: nr_in
   real(ReKi), dimension(:), allocatable :: rPrescr, GammaPrescr !< Radius 
   nr_in = size(Gamma_LL)
   call GetNewUnit(iUnit)
   open(unit = iUnit, file = './PrescribedGamma.txt')  ! TODO more general
   read(iUnit,*)nr
   if (nr/=nr_in)  then
      write(*,*)'[ERROR] Number of prescribed point different from number of BS'
      STOP 1
   endif
   allocate(rPrescr(1:nr),GammaPrescr(1:nr))
   do i=1,nr
      read(iUnit,*) rPrescr(i), GammaPrescr(i)
   enddo
   close(iUnit)
   ! -- This part is the only part we need once the thing above has been moved
   do i=1,nr
      Gamma_LL(i)=GammaPrescr(i)
   enddo
endsubroutine Prescribe_Gamma

!> Establish the list of points where we will need the free stream
subroutine SetRequestedWindPoints(r_wind, x, p, m, ErrStat, ErrMsg )
   real(ReKi), dimension(:,:), allocatable,      intent(inout) :: r_wind  !< Position where wind is requested
   type(FVW_ContinuousStateType),   intent(in   )              :: x       !< States
   type(FVW_ParameterType),         intent(in   )              :: p       !< Parameters
   type(FVW_MiscVarType),           intent(in   )              :: m       !< Initial misc/optimization variables
   integer(IntKi),                  intent(  out)              :: ErrStat !< Error status of the operation
   character(*),                    intent(  out)              :: ErrMsg  !< Error message if ErrStat /= ErrID_None
   integer(IntKi)          :: ErrStat2       ! temporary error status of the operation
   character(ErrMsgLen)    :: ErrMsg2        ! temporary error message
   integer(IntKi)          :: nTot              ! Total number of points
   integer(IntKi)          :: iSpan, iW, iAge   ! Index on span, wings, panels
   integer(IntKi)          :: iP                ! Current index of point
   ! Initialize ErrStat
   ErrStat = ErrID_None
   ErrMsg  = ""
   if (allocated(r_wind)) deallocate(r_wind)

   nTot = 0
   nTot = nTot + p%nWings *  p%nSpan                ! Lifting line Control Points
   nTot = nTot + p%nWings * (p%nSpan+1) * (m%nNW+1) ! Nearwake points
   nTot = nTot + p%nWings * (   1   +1) * (m%nFW+1) ! War wake points

   call AllocAry( r_wind , 3, nTot, 'Requested Wind Points', ErrStat2, ErrMsg2 );call SetErrStat(ErrStat2, ErrMsg2, ErrStat,ErrMsg,'SetRequestedWindPoints'); 
   r_wind(1:3,1:nTot)= -999999_ReKi;

   iP=0

   ! --- LL CP
   do iW = 1, p%nWings
      do iSpan = 1, p%nSpan
         iP=iP+1
         r_wind(1:3,iP) = m%CP_LL(1:3, iSpan, iW)
      enddo
   enddo

   ! --- NW points
   do iW = 1, p%nWings
      do iSpan = 1, p%nSpan + 1
         do iAge = 1, m%nNW + 1
            iP=iP+1
            r_wind(1:3,iP) = x%r_NW(1:3, iSpan, iAge, iW)
         enddo
      enddo
   enddo

   ! --- FW points
   do iW = 1, p%nWings
      do iSpan = 1, 2 ! root and tip
         do iAge = 1, m%nFW + 1
            iP=iP+1
            r_wind(1:3,iP) = x%r_FW(1:3, iSpan, iAge, iW)
         enddo
      enddo
   enddo
end subroutine SetRequestedWindPoints


!> Set the requested wind into the correponding misc variables
subroutine DistributeRequestedWind(V_wind, x, p, m, ErrStat, ErrMsg )
   real(ReKi), dimension(:,:),      intent(in   ) :: V_wind  !< Position where wind is requested
   type(FVW_ContinuousStateType),   intent(in   ) :: x       !< States
   type(FVW_ParameterType),         intent(in   ) :: p       !< Parameters
   type(FVW_MiscVarType),           intent(inout) :: m       !< Initial misc/optimization variables
   integer(IntKi),                  intent(  out) :: ErrStat !< Error status of the operation
   character(*),                    intent(  out) :: ErrMsg  !< Error message if ErrStat /= ErrID_None
   integer(IntKi)          :: ErrStat2       ! temporary error status of the operation
   character(ErrMsgLen)    :: ErrMsg2        ! temporary error message
   integer(IntKi)          :: nTot              ! Total number of points
   integer(IntKi)          :: iSpan, iW, iAge   ! Index on span, wings, panels
   integer(IntKi)          :: iP                ! Current index of point
   ! Initialize ErrStat
   ErrStat = ErrID_None
   ErrMsg  = ""

   ! nTot, for satefy check
   nTot = 0
   nTot = nTot + p%nWings *  p%nSpan                ! Lifting line Control Points
   nTot = nTot + p%nWings * (p%nSpan+1) * (m%nNW+1) ! Nearwake points
   nTot = nTot + p%nWings * (   1   +1) * (m%nFW+1) ! War wake points
   if (size(V_wind,2)<nTot) then
      print*,'Wrong number of points, expecting:',nTot,' got:', size(V_wind,2)
      STOP
   endif

   iP=0
   ! --- LL CP
   do iW = 1, p%nWings
      do iSpan = 1, p%nSpan
         iP=iP+1
         m%Vwnd_LL(1:3, iSpan, iW) = V_wind(1:3,iP)
      enddo
   enddo

   ! --- NW points
   do iW = 1, p%nWings
      do iSpan = 1, p%nSpan + 1
         do iAge = 1, m%nNW + 1
            iP=iP+1
            m%Vwnd_NW(1:3, iSpan, iAge, iW) = V_wind(1:3,iP)
         enddo
      enddo
   enddo

   ! --- FW points
   do iW = 1, p%nWings
      do iSpan = 1, 2 ! root and tip
         do iAge = 1, m%nFW + 1
            iP=iP+1
            m%Vwnd_NW(1:3, iSpan, iAge, iW) = V_wind(1:3,iP)
         enddo
      enddo
   enddo

end subroutine DistributeRequestedWind


!> Distribute the induced velocity to the proper location 
subroutine UnPackInducedVelocity(p, m, x, Uind)
   type(FVW_ParameterType),         intent(in   ) :: p       !< Parameters
   type(FVW_MiscVarType),           intent(inout) :: m       !< Initial misc/optimization variables
   type(FVW_ContinuousStateType),   intent(in   ) :: x       !< States
   real(ReKi), dimension(:,:)   ,   intent(in   ) :: Uind    !< Induced velocity
   ! Local
   integer(IntKi) :: iW, iHeadP
   iHeadP=1
   do iW=1,p%nWings
      CALL VecToLattice(Uind, 1, m%Vind_NW(:,:,1:m%nNW+1,iW), iHeadP)
   enddo
   if ((iHeadP-1)/=size(Uind,2)) then
      print*,'UnPackInducedVelocity: Number of points wrongly estimated',size(Uind,2), iHeadP-1
      STOP
   endif
end subroutine


!> Distribute the induced velocity to the convecting points
subroutine PackConvectingPoints(p, m, x, Points, nPoints)
   type(FVW_ParameterType),         intent(in   ) :: p       !< Parameters
   type(FVW_MiscVarType),           intent(in   ) :: m       !< Initial misc/optimization variables
   type(FVW_ContinuousStateType),   intent(in   ) :: x       !< States
   real(ReKi), dimension(:,:)   ,   intent(inout) :: Points  !< Points packed
   integer(IntKi),                  intent(  out) :: nPoints  !< Number of points packed
   ! Local
   integer(IntKi) :: iW, iHeadP

   ! --- Compute number of convecting points
   iHeadP=1
   do iW=1,p%nWings
      CALL LatticeToPoints(x%r_NW(1:3,:,1:m%nNW+1,iW), 1, Points, iHeadP)
   enddo
   if ((iHeadP-1)/=size(Points,2)) then
      print*,'PackConvectingPoints: Number of points wrongly estimated',size(Points,2), iHeadP-1
      STOP
   endif
   nPoints=iHeadP-1
end subroutine

subroutine PackPanelsToSegments(p, m, x, iNWStart, SegConnct, SegPoints, SegGamma, nSeg, nSegP)
   type(FVW_ParameterType),         intent(in   ) :: p       !< Parameters
   type(FVW_MiscVarType),           intent(in   ) :: m       !< Initial misc/optimization variables
   type(FVW_ContinuousStateType),   intent(in   ) :: x       !< States
   integer(IntKi),                  intent(in   ) :: iNWStart !< Index where we start packing for NW panels
   integer(IntKi),dimension(:,:), allocatable :: SegConnct !< Segment connectivity
   real(ReKi),    dimension(:,:), allocatable :: SegPoints !< Segment Points
   real(ReKi),    dimension(:)  , allocatable :: SegGamma  !< Segment Circulation
   integer(IntKi), intent(out)                :: nSeg      !< Total number of segments after packing
   integer(IntKi), intent(out)                :: nSegP     !< Total number of segments points after packing
   ! Local
   integer(IntKi) :: iHeadC, iHeadP, nC, nP, iW
   real(ReKi), dimension(:,:), allocatable :: Buffer2d
   !real(ReKi),    dimension(:),   allocatable :: SegSmooth !< 

   ! Counting total number of segments TODO add FarWake
   nP =      p%nWings * (  (p%nSpan+1)*(m%nNW-iNWStart+2)            )
   nC =      p%nWings * (2*(p%nSpan+1)*(m%nNW-iNWStart+2)-(p%nSpan+1)-(m%nNW-iNWStart+1+1))  
!    nP = nP + p%nWings * (p%nSpan+1)*2
!    nC = nC + p%nWings * (2*(p%nSpan+1)*(2)-p%nSpan-1-2)

   if (allocated(SegConnct)) deallocate(SegConnct)
   if (allocated(SegPoints)) deallocate(SegPoints)
   if (allocated(SegGamma))  deallocate(SegGamma)
   if (allocated(Buffer2d)) deallocate(Buffer2d)
   allocate(SegConnct(1:2,1:nC)); SegConnct=-1
   allocate(SegPoints(1:3,1:nP)); SegPoints=-1
   allocate(SegGamma (1:nC));     SegGamma =-1
   allocate(Buffer2d(1,p%nSpan))
   !
   iHeadP=1
   iHeadC=1
   do iW=1,p%nWings
      CALL LatticeToSegments(x%r_NW(1:3,:,1:m%nNW+1,iW), x%Gamma_NW(:,1:m%nNW,iW), iNWStart, SegPoints, SegConnct, SegGamma, iHeadP, iHeadC )
   enddo
   if ((iHeadP-1)/=nP) then
      print*,'PackPanelsToSegments: Number of points wrongly estimated',nP, iHeadP-1
      STOP
   endif
   if ((iHeadC-1)/=nC) then
      print*,'PackPanelsToSegments: Number of segments wrongly estimated',nC, iHeadC-1
      STOP
   endif
   nSeg  = iHeadC-1
   nSegP = iHeadP-1
end subroutine PackPanelsToSegments

subroutine WakeInducedVelocities(p, x, m, ErrStat, ErrMsg)
   type(FVW_ParameterType),         intent(in   ) :: p       !< Parameters
   type(FVW_ContinuousStateType),   intent(in   ) :: x       !< States
   type(FVW_MiscVarType),           intent(inout) :: m       !< Initial misc/optimization variables
   ! Local variables
   integer(IntKi) :: SmoothModel !< TODO input file parameter
   integer(IntKi) :: iSpan,iAge, iW, nSeg, nSegP, nCPs
   integer(IntKi),dimension(:,:), allocatable :: SegConnct !< Segment connectivity
   real(ReKi),    dimension(:,:), allocatable :: SegPoints !< Segment Points
   real(ReKi),    dimension(:)  , allocatable :: SegGamma  !< Segment Circulation
   real(ReKi),    dimension(:)  , allocatable :: SegSmooth  !< Segment smooth parameter
   real(ReKi),    dimension(:,:), allocatable :: CPs   !< ControlPoints
   real(ReKi),    dimension(:,:), allocatable :: Uind  !< Induced velocity
   integer(IntKi),              intent(  out) :: ErrStat    !< Error status of the operation
   character(*),                intent(  out) :: ErrMsg     !< Error message if ErrStat /= ErrID_None

   m%Vind_NW = -9999._ReKi !< Safety
   m%Vind_FW = -9999._ReKi !< Safety

   ! --- Packing all vortex elements into a list of segments
   call PackPanelsToSegments(p, m, x, 1, SegConnct, SegPoints, SegGamma, nSeg, nSegP)
   print*,'Number of segments',nSeg, 'Number of points',nSegP
   ! 
   ! --- Computing induced velocity
   allocate(SegSmooth(1:nSeg));
   SegSmooth=10
   SmoothModel=idSegSmoothLambOseen
   nCPs=nSegP
   allocate(CPs (1:3,1:nCPs))
   allocate(Uind(1:3,1:nCPs))
   Uind=0.0_ReKi !< important due to side effects of ui_seg
   ! ---
   call PackConvectingPoints(p, m, x, CPs, nCPs)
   print*,'Number of points packed for Convection:',nCPs, nSegP
   CALL ui_seg( 1, nCPs, nCPs, CPs, &
      1, nSeg, nSeg, nSegP, SegPoints, SegConnct, SegGamma,   &
      SmoothModel, SegSmooth, Uind)
   call UnPackInducedVelocity(p, m, x, Uind)

   deallocate(Uind)
   deallocate(CPs)
   deallocate(SegConnct)
   deallocate(SegGamma)
   deallocate(SegPoints)
   deallocate(SegSmooth)
end subroutine




end module FVW_Subs
