cc Copyright (C) 2017-2018: Leslie Greengard, Zydrunas Gimbutas, and
cc and Manas Rachh
cc Contact: greengard@cims.nyu.edu
cc 
cc This program is free software; you can redistribute it and/or modify 
cc it under the terms of the GNU General Public License as published by 
cc the Free Software Foundation; either version 2 of the License, or 
cc (at your option) any later version.  This program is distributed in 
cc the hope that it will be useful, but WITHOUT ANY WARRANTY; without 
cc even the implied warranty of MERCHANTABILITY or FITNESS FOR A 
cc PARTICULAR PURPOSE.  See the GNU General Public License for more 
cc details. You should have received a copy of the GNU General Public 
cc License along with this program; 
cc if not, see <http://www.gnu.org/licenses/>.
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
c
c    $Date$
c    $Revision$
c
       subroutine lfmm3d(nd,eps,nsource,source,ifcharge,
     $    charge,ifdipole,dipvec,ifpgh,pot,grad,hess,ntarg,
     $    targ,ifpghtarg,pottarg,gradtarg,hesstarg)
c
c        Laplace FMM in R^{3}: evaluate all pairwise particle
c        interactions (ignoring self-interactions) and interactions
c        with targs.
c
c        We use (1/r) for the Green's function, without the
c        1/(4 \pi) scaling.
c
c
c        Input parameters:
c
c   nd:   number of densities
c
c   eps:  requested precision
c
c   nsource in: integer  
c                number of sources
c
c   source  in: double precision (3,nsource)
c                source(k,j) is the kth component of the jth
c                source locations
c
c   ifcharge  in: integer  
c             charge computation flag
c              ifcharge = 1   =>  include charge contribution
c                                     otherwise do not
c 
c   charge    in: double precision (nsource) 
c              charge strengths
c
c   ifdipole   in: integer
c              dipole computation flag
c              ifdipole = 1   =>  include dipole contribution
c                                     otherwise do not
c
c
c   dipvec   in: double precision (3,nsource) 
c              dipole orientation vectors
c
c   ifpgh   in: integer
c              flag for evaluating potential/gradient at the sources
c              ifpgh = 1, only potential is evaluated
c              ifpgh = 2, potential and gradients are evaluated
c
c   ntarg  in: integer  
c                 number of targs 
c
c   targ  in: double precision (3,ntarg)
c               targ(k,j) is the kth component of the jth
c               targ location
c
c   ifpghtarg   in: integer
c              flag for evaluating potential/gradient at the targs
c              ifpghtarg = 1, only potential is evaluated
c              ifpghtarg = 2, potential and gradient are evaluated
c
c
c     OUTPUT parameters:
c
c
c   pot:    out: double precision(nd,nsource) 
c               potential at the source locations
c
c   grad:   out: double precision(nd,3,nsource)
c               gradient at the source locations
c
c   hess    out: double precision(nd,6,nsource)
c               hessian at the source locations
c                 (currently not supported)
c
c   pottarg:    out: double precision(nd,ntarg) 
c               potential at the targ locations
c
c   gradtarg:   out: double precision(nd,3,ntarg)
c               gradient at the targ locations
c
c   hesstarg    out: double precision(nd,6,ntarg)
c                hessian at the target locations - currently not
c                supported
     
       implicit none

       integer nd

       double precision eps

       integer ifcharge,ifdipole
       integer ifpgh,ifpghtarg

       integer ntarg,nsource


       double precision source(3,*),targ(3,*)
       double precision charge(nd,*)
       double precision dipvec(nd,3,*)

       double precision pot(nd,*),grad(nd,3,*),hess(nd,6,*)
       double precision pottarg(nd,*),gradtarg(nd,3,*),hesstarg(nd,6,*)

c
cc       tree variables
c
       integer ltree,mhung,idivflag,ndiv,isep,nboxes,nbmax,nlevels
       integer nlmax
       integer mnbors,mnlist1,mnlist2,mnlist3,mnlist4
       integer ipointer(32)
       integer, allocatable :: itree(:)
       double precision, allocatable :: treecenters(:,:),boxsize(:)

c
cc       temporary sorted arrays
c
       double precision, allocatable :: sourcesort(:,:),targsort(:,:)
       double precision, allocatable :: radsrc(:)
       double precision, allocatable :: chargesort(:,:)
       double precision, allocatable :: dipvecsort(:,:,:)

       double precision, allocatable :: potsort(:,:),gradsort(:,:,:)
       double precision, allocatable :: hesssort(:,:,:)
       double precision, allocatable :: pottargsort(:,:)
       double precision, allocatable :: gradtargsort(:,:,:)
       double precision, allocatable :: hesstargsort(:,:,:)
c
cc        temporary fmm arrays
c
       double precision epsfmm
       integer, allocatable :: nterms(:),iaddr(:,:)
       double precision, allocatable :: scales(:)
       double precision, allocatable :: rmlexp(:)

       integer lmptemp,nmax,lmptot
       double precision, allocatable :: mptemp(:),mptemp2(:)

c
cc       temporary variables not main fmm routine but
c        not used in particle code
       double precision expc(3),scjsort(1),radexp
       double complex texpssort(100)
       double precision expcsort(3)
       integer ntj,nexpc,nadd

c
cc         other temporary variables
c
        integer i,iert,ifprint,ilev,idim,ier
        double precision time1,time2,omp_get_wtime,second

c
cc        figure out tree structure
c
c
cc         set criterion for box subdivision
c

       ndiv = 100

c
cc      set tree flags
c 
       isep = 1
       nlmax = 200
       nlevels = 0
       nboxes = 0
       mhung = 0
       ltree = 0

       nexpc = 0
       nadd = 0
       ntj = 0

       idivflag = 0

       mnlist1 = 0
       mnlist2 = 0
       mnlist3 = 0
       mnlist4 = 0
       nbmax = 0


       allocate(radsrc(nsource))
C$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(i)       
       do i=1,nsource
          radsrc(i) = 0
       enddo
C$OMP END PARALLEL DO  

       radexp = 0

c
cc     memory management code for contructing level restricted tree
        iert = 0
        call mklraptreemem(iert,source,nsource,radsrc,targ,ntarg,
     1        expc,nexpc,radexp,idivflag,ndiv,isep,nlmax,nbmax,
     2        nlevels,nboxes,mnbors,mnlist1,mnlist2,mnlist3,
     3        mnlist4,mhung,ltree)



        if(iert.ne.0) then
           call prin2('Error in allocating tree memory, ier=*',ier,1)
           stop
        endif


        allocate(itree(ltree))
        allocate(boxsize(0:nlevels))
        allocate(treecenters(3,nboxes))

c       Call tree code
        call mklraptree(source,nsource,radsrc,targ,ntarg,expc,
     1               nexpc,radexp,idivflag,ndiv,isep,mhung,mnbors,
     2               mnlist1,mnlist2,mnlist3,mnlist4,nlevels,
     2               nboxes,treecenters,boxsize,itree,ltree,ipointer)

c
c
c     ifprint is an internal information printing flag. 
c     Suppressed if ifprint=0.
c     Prints timing breakdown and other things if ifprint=1.
c       
      ifprint=0

c     Allocate sorted source and targ arrays      

      allocate(sourcesort(3,nsource))
      allocate(targsort(3,ntarg))
      if(ifcharge.eq.1) allocate(chargesort(nd,nsource))

      if(ifdipole.eq.1) then
         allocate(dipvecsort(nd,3,nsource))
      endif

      if(ifpgh.eq.1) then 
        allocate(potsort(nd,nsource),gradsort(nd,3,1),hesssort(nd,6,1))
      else if(ifpgh.eq.2) then
        allocate(potsort(nd,nsource),gradsort(nd,3,nsource),
     1       hesssort(nd,6,1))
      else if(ifpgh.eq.3) then
        allocate(potsort(nd,nsource),gradsort(nd,3,nsource),
     1       hesssort(nd,6,nsource))
      else
        allocate(potsort(nd,1),gradsort(nd,3,1),hesssort(nd,6,1))
      endif

      if(ifpghtarg.eq.1) then
        allocate(pottargsort(nd,ntarg),gradtargsort(nd,3,1),
     1      hesstargsort(nd,6,1))
      else if(ifpghtarg.eq.2) then
        allocate(pottargsort(nd,ntarg),gradtargsort(nd,3,ntarg),
     1        hesstargsort(nd,6,1))
      else if(ifpghtarg.eq.3) then
        allocate(pottargsort(nd,ntarg),gradtargsort(nd,3,ntarg),
     1        hesstargsort(nd,6,ntarg))
      else
        allocate(pottargsort(nd,1),gradtargsort(nd,3,1),
     1     hesstargsort(nd,6,1))
      endif


c     scaling factor for multipole and local expansions at all levels
c
      allocate(scales(0:nlevels),nterms(0:nlevels))
      do ilev = 0,nlevels
        scales(ilev) = boxsize(ilev)
      enddo
c
cc      initialize potential and gradient at source
c       locations
c
      if(ifpgh.eq.1) then
C$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(i,idim)
        do i=1,nsource
          do idim=1,nd
            potsort(idim,i) = 0
          enddo
        enddo
C$OMP END PARALLEL DO
      endif

      if(ifpgh.eq.2) then
C$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(i,idim)

        do i=1,nsource
          do idim=1,nd
            potsort(idim,i) = 0
            gradsort(idim,1,i) = 0
            gradsort(idim,2,i) = 0
            gradsort(idim,3,i) = 0
          enddo
        enddo
C$OMP END PARALLEL DO
      endif


      if(ifpgh.eq.3) then
C$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(i,idim)
        do i=1,nsource
          do idim=1,nd
            potsort(idim,i) = 0
            gradsort(idim,1,i) = 0
            gradsort(idim,2,i) = 0
            gradsort(idim,3,i) = 0
            hesssort(idim,1,i) = 0
            hesssort(idim,2,i) = 0
            hesssort(idim,3,i) = 0
            hesssort(idim,4,i) = 0
            hesssort(idim,5,i) = 0
            hesssort(idim,6,i) = 0
          enddo
        enddo
C$OMP END PARALLEL DO
      endif



c
cc       initialize potential and gradient  at targ
c        locations
c
      if(ifpghtarg.eq.1) then
C$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(i,idim)
        do i=1,ntarg
          do idim=1,nd
            pottargsort(idim,i) = 0
          enddo
        enddo
C$OMP END PARALLEL DO
      endif

      if(ifpghtarg.eq.2) then
C$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(i,idim)
        do i=1,ntarg
          do idim=1,nd
            pottargsort(idim,i) = 0
            gradtargsort(idim,1,i) = 0
            gradtargsort(idim,2,i) = 0
            gradtargsort(idim,3,i) = 0
          enddo
        enddo
C$OMP END PARALLEL DO
      endif

      if(ifpghtarg.eq.3) then
C$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(i,idim)
        do i=1,ntarg
          do idim=1,nd
            pottargsort(idim,i) = 0
            gradtargsort(idim,1,i) = 0
            gradtargsort(idim,2,i) = 0
            gradtargsort(idim,3,i) = 0
            hesstargsort(idim,1,i) = 0
            hesstargsort(idim,2,i) = 0
            hesstargsort(idim,3,i) = 0
            hesstargsort(idim,4,i) = 0
            hesstargsort(idim,5,i) = 0
            hesstargsort(idim,6,i) = 0
          enddo
        enddo
C$OMP END PARALLEL DO
      endif

c     Compute length of expansions at each level      
      nmax = 0
      do i=0,nlevels
         call l3dterms(eps,nterms(i))
         if(nterms(i).gt.nmax) nmax = nterms(i)
      enddo
c       
c     Multipole and local expansions will be held in workspace
c     in locations pointed to by array iaddr(2,nboxes).
c
c     iaddr is pointer to iaddr array, itself contained in workspace.
c     imptemp is pointer for single expansion (dimensioned by nmax)
c
c       ... allocate iaddr and temporary arrays
c

      allocate(iaddr(2,nboxes))
      lmptemp = (nmax+1)*(2*nmax+1)*2*nd
      allocate(mptemp(lmptemp),mptemp2(lmptemp))

c
cc     reorder sources 
c
      call dreorderf(3,nsource,source,sourcesort,itree(ipointer(5)))
      if(ifcharge.eq.1) call dreorderf(nd,nsource,charge,chargesort,
     1                     itree(ipointer(5)))

      if(ifdipole.eq.1) then
         call dreorderf(3*nd,nsource,dipvec,dipvecsort,
     1       itree(ipointer(5)))
      endif

c
cc      reorder targs
c
      call dreorderf(3,ntarg,targ,targsort,itree(ipointer(6)))
c
c     allocate memory need by multipole, local expansions at all
c     levels
c     irmlexp is pointer for workspace need by various fmm routines,
c
      call mpalloc(nd,itree(ipointer(1)),iaddr,nlevels,lmptot,nterms)
      if(ifprint.ge. 1) call prinf(' lmptot is *',lmptot,1)


      allocate(rmlexp(lmptot),stat=ier)
      if(ier.ne.0) then
        call prinf('Cannot allocate mpole expansion workspace,
     1              lmptot is *', lmptot,1)
        ier = 16
        stop
      endif

c     Memory allocation is complete. 
c     Call main fmm routine

      time1=second()
C$      time1=omp_get_wtime()
      call lfmm3dmain(nd,eps,
     $   nsource,sourcesort,
     $   ifcharge,chargesort,
     $   ifdipole,dipvecsort,
     $   ntarg,targsort,nexpc,expcsort,
     $   epsfmm,iaddr,rmlexp,lmptot,mptemp,mptemp2,lmptemp,
     $   itree,ltree,ipointer,isep,ndiv,nlevels,
     $   nboxes,boxsize,mnbors,mnlist1,mnlist2,mnlist3,mnlist4,
     $   scales,treecenters,itree(ipointer(1)),nterms,
     $   ifpgh,potsort,gradsort,hesssort,
     $   ifpghtarg,pottargsort,gradtargsort,hesstargsort,ntj,
     $   texpssort,scjsort)

      time2=second()
C$        time2=omp_get_wtime()
      if( ifprint .eq. 1 ) call prin2('time in fmm main=*',
     1   time2-time1,1)



      if(ifpgh.eq.1) then
        call dreorderi(nd,nsource,potsort,pot,
     1                 itree(ipointer(5)))
      endif
      if(ifpgh.eq.2) then 
        call dreorderi(nd,nsource,potsort,pot,
     1                 itree(ipointer(5)))
        call dreorderi(3*nd,nsource,gradsort,grad,
     1                 itree(ipointer(5)))
      endif

      if(ifpgh.eq.3) then 
        call dreorderi(nd,nsource,potsort,pot,
     1                 itree(ipointer(5)))
        call dreorderi(3*nd,nsource,gradsort,grad,
     1                 itree(ipointer(5)))
        call dreorderi(6*nd,nsource,hesssort,hess,
     1                 itree(ipointer(5)))
      endif


      if(ifpghtarg.eq.1) then
        call dreorderi(nd,ntarg,pottargsort,pottarg,
     1     itree(ipointer(6)))
      endif

      if(ifpghtarg.eq.2) then
        call dreorderi(nd,ntarg,pottargsort,pottarg,
     1     itree(ipointer(6)))
        call dreorderi(3*nd,ntarg,gradtargsort,gradtarg,
     1     itree(ipointer(6)))
      endif

      if(ifpghtarg.eq.3) then
        call dreorderi(nd,ntarg,pottargsort,pottarg,
     1     itree(ipointer(6)))
        call dreorderi(3*nd,ntarg,gradtargsort,gradtarg,
     1     itree(ipointer(6)))
        call dreorderi(6*nd,ntarg,hesstargsort,hesstarg,
     1     itree(ipointer(6)))
      endif

      return
      end

c       
c---------------------------------------------------------------
c
      subroutine lfmm3dmain(nd,eps,
     $     nsource,sourcesort,
     $     ifcharge,chargesort,
     $     ifdipole,dipvecsort,
     $     ntarg,targsort,nexpc,expcsort,
     $     epsfmm,iaddr,rmlexp,lmptot,mptemp,mptemp2,lmptemp,
     $     itree,ltree,ipointer,isep,ndiv,nlevels, 
     $     nboxes,boxsize,mnbors,mnlist1,mnlist2,mnlist3,mnlist4,
     $     rscales,centers,laddr,nterms,
     $     ifpgh,pot,grad,hess,
     $     ifpghtarg,pottarg,gradtarg,hesstarg,ntj,
     $     tsort,scjsort)
      implicit none

      integer nd
      double precision eps
      integer nsource,ntarg,nexpc
      integer ndiv,nlevels

      integer ifcharge,ifdipole
      integer ifpgh,ifpghtarg
      double precision epsfmm

      double precision sourcesort(3,nsource)

      double precision chargesort(nd,*)
      double precision dipvecsort(nd,3,*)

      double precision targsort(3,ntarg)

      double precision pot(nd,*),grad(nd,3,*),hess(nd,6,*)
      double precision pottarg(nd,*),gradtarg(nd,3,*),hesstarg(nd,6,*)

      integer ntj
      double precision expcsort(3,nexpc)
      double complex tsort(nd,0:ntj,-ntj:ntj,nexpc)
      double precision scjsort(nexpc)

      integer iaddr(2,nboxes), lmptot, lmptemp
      double precision rmlexp(lmptot)
      double precision mptemp(lmptemp)
      double precision mptemp2(lmptemp)

      double precision thresh
       
      double precision timeinfo(10)
      double precision centers(3,nboxes)

      integer isep, ltree
      integer laddr(2,0:nlevels)
      integer nterms(0:nlevels)
      integer ipointer(32)
      integer itree(ltree)
      integer nboxes
      double precision rscales(0:nlevels)
      double precision boxsize(0:nlevels)

      integer nuall,ndall,nnall,nsall,neall,nwall
      integer nu1234,nd5678,nn1256,ns3478,ne1357,nw2468
      integer nn12,nn56,ns34,ns78,ne13,ne57,nw24,nw68
      integer ne1,ne3,ne5,ne7,nw2,nw4,nw6,nw8

      integer uall(200),dall(200),nall(120),sall(120),eall(72),wall(72)
      integer u1234(36),d5678(36),n1256(24),s3478(24)
      integer e1357(16),w2468(16),n12(20),n56(20),s34(20),s78(20)
      integer e13(20),e57(20),w24(20),w68(20)
      integer e1(20),e3(5),e5(5),e7(5),w2(5),w4(5),w6(5),w8(5)

c     temp variables
      integer i,j,k,l,ii,jj,kk,ll,m,idim
      integer ibox,jbox,ilev,npts,npts0
      integer nchild,nlist1,nlist2,nlist3,nlist4

      integer istart,iend,istarts,iends
      integer istartt,iendt,istarte,iende
      integer isstart,isend,jsstart,jsend
      integer jstart,jend

      integer ifprint

      double precision d,time1,time2,second,omp_get_wtime
      double precision pottmp,fldtmp(3),hesstmp(3)

c     PW variables
      integer ntmax, nexpmax, nlams, nmax, nthmax, nphmax,nmax2
      parameter (ntmax = 40)
      parameter (nexpmax = 1600)
      integer lca
      double precision, allocatable :: carray(:,:), dc(:,:)
      double precision, allocatable :: cs(:,:),fact(:),rdplus(:,:,:)
      double precision, allocatable :: rdminus(:,:,:), rdsq3(:,:,:)
      double precision, allocatable :: rdmsq3(:,:,:)
  
      double precision rlams(ntmax), whts(ntmax)

      double precision, allocatable :: rlsc(:,:,:)
      integer nfourier(ntmax), nphysical(ntmax)
      integer nexptot, nexptotp
      double complex, allocatable :: xshift(:,:)
      double complex, allocatable :: yshift(:,:)
      double precision, allocatable :: zshift(:,:)

      double complex fexpe(50000), fexpo(50000), fexpback(100000)
      double complex, allocatable :: mexp(:,:,:,:)
      double complex, allocatable :: mexpf1(:,:),mexpf2(:,:)
      double complex, allocatable ::
     1       mexpp1(:,:),mexpp2(:,:),mexppall(:,:,:)

      double complex, allocatable :: tmp(:,:,:)

      double precision sourcetmp(3)
      double complex chargetmp

      integer ix,iy,iz,ictr
      double precision rtmp
      double complex zmul

      integer nlege, lw7, lused7, itype
      double precision wlege(40000)
      integer nterms_eval(4,0:nlevels)

      integer mnlist1, mnlist2,mnlist3,mnlist4,mnbors
      double complex eye, ztmp
      double precision alphaj
      integer ctr,nn,iptr1,iptr2
      double precision, allocatable :: rscpow(:)
      double precision pi,errtmp
      double complex ima
      data ima/(0.0d0,1.0d0)/

      pi = 4.0d0*atan(1.0d0)

      thresh = 1.0d-16*boxsize(0)
      

c     Initialize routines for plane wave mp loc translation
 
      if(isep.eq.1) then
         if(eps.ge.0.5d-3) nlams = 12
         if(eps.lt.0.5d-3.and.eps.ge.0.5d-6) nlams = 20
         if(eps.lt.0.5d-6.and.eps.ge.0.5d-9) nlams = 29
         if(eps.lt.0.5d-9) nlams = 37
      endif
      if(isep.eq.2) then
         if(eps.ge.0.5d-3) nlams = 9
         if(eps.lt.0.5d-3.and.eps.ge.0.5d-6) nlams = 15
         if(eps.lt.0.5d-6.and.eps.ge.0.5d-9) nlams = 22
         if(eps.lt.0.5d-9) nlams = 29
      endif

      nmax = 0
      do i=0,nlevels
         if(nmax.lt.nterms(i)) nmax = nterms(i)
      enddo
      allocate(rscpow(0:nmax))
      allocate(carray(4*nmax+1,4*nmax+1))
      allocate(dc(0:4*nmax,0:4*nmax))
      allocate(rdplus(0:nmax,0:nmax,-nmax:nmax))
      allocate(rdminus(0:nmax,0:nmax,-nmax:nmax))
      allocate(rdsq3(0:nmax,0:nmax,-nmax:nmax))
      allocate(rdmsq3(0:nmax,0:nmax,-nmax:nmax))
      allocate(rlsc(0:nmax,0:nmax,nlams))


c     generate rotation matrices and carray
      call getpwrotmat(nmax,carray,rdplus,rdminus,rdsq3,rdmsq3,dc)


c     generate rlams and weights (these are the nodes
c     and weights for the lambda integral)

      if(isep.eq.1) call vwts(rlams,whts,nlams)
      if(isep.eq.2) call lwtsexp3sep2(nlams,rlams,whts,errtmp)


c     generate the number of fourier modes required to represent the
c     moment function in fourier space

      if(isep.eq.1) call numthetahalf(nfourier,nlams)
      if(isep.eq.2) call numthetahalf_isep2(nfourier,nlams)
 
c     generate the number of fourier modes in physical space
c     required for the exponential representation
      if(isep.eq.1) call numthetafour(nphysical,nlams)
      if(isep.eq.2) call numthetasix(nphysical,nlams)

c     Generate powers of lambda for the exponential basis
      call rlscini(rlsc,nlams,rlams,nmax)

c     Compute total number of plane waves
      nexptotp = 0
      nexptot = 0
      nthmax = 0
      nphmax = 0
      do i=1,nlams
         nexptot = nexptot + nfourier(i)
         nexptotp = nexptotp + nphysical(i)
         if(nfourier(i).gt.nthmax) nthmax = nfourier(i)
         if(nphysical(i).gt.nphmax) nphmax = nphysical(i)
      enddo
      allocate(tmp(nd,0:nmax,-nmax:nmax))

      allocate(xshift(-5:5,nexptotp))
      allocate(yshift(-5:5,nexptotp))
      allocate(zshift(5,nexptotp))

      allocate(mexpf1(nd,nexptot),mexpf2(nd,nexptot),
     1   mexpp1(nd,nexptotp))
      allocate(mexpp2(nd,nexptotp),mexppall(nd,nexptotp,16))

      allocate(mexp(nd,nexptotp,nboxes,6))

c     Precompute table for shifting exponential coefficients in 
c     physical domain
      call mkexps(rlams,nlams,nphysical,nexptotp,xshift,yshift,zshift)

c     Precompute table of exponentials for mapping from
c     fourier to physical domain
      call mkfexp(nlams,nfourier,nphysical,fexpe,fexpo,fexpback)
      
c
cc    compute array of factorials

     
      nmax2 = 2*nmax
      allocate(fact(0:nmax2),cs(0:nmax,-nmax:nmax))
      
      d = 1
      fact(0) = d
      do i=1,nmax2
        d=d*sqrt(i+0.0d0)
        fact(i) = d
      enddo

      cs(0,0) = 1.0d0
      do l=1,nmax
        do m=0,l
          cs(l,m) = ((-1)**l)/(fact(l-m)*fact(l+m))
          cs(l,-m) = cs(l,m)
        enddo
      enddo


      
c     ifprint is an internal information printing flag. 
c     Suppressed if ifprint=0.
c     Prints timing breakdown and other things if ifprint=1.
c     Prints timing breakdown, list information, 
c     and other things if ifprint=2.
c       
      ifprint=0
      if(ifprint.ge.1) 
     1   call prin2('end of generating plane wave info*',i,0)
c
c
c     ... set the expansion coefficients to zero
c
C$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(i,j,k,idim)
      do i=1,nexpc
        do k=-ntj,ntj
          do j = 0,ntj
            do idim=1,nd
              tsort(idim,j,k,i)=0
            enddo
          enddo
        enddo
      enddo
C$OMP END PARALLEL DO

c       
      do i=1,10
        timeinfo(i)=0
      enddo

c
c       ... set all multipole and local expansions to zero
c

      do ilev = 0,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox)
        do ibox=laddr(1,ilev),laddr(2,ilev)
          call mpzero(nd,rmlexp(iaddr(1,ibox)),nterms(ilev))
          call mpzero(nd,rmlexp(iaddr(2,ibox)),nterms(ilev))
        enddo
C$OMP END PARALLEL DO        
      enddo

c
c      set scjsort
c
      do ilev=0,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,nchild,istart,iend,i)
         do ibox=laddr(1,ilev),laddr(2,ilev)
            nchild = itree(ipointer(3)+ibox-1)
            if(nchild.gt.0) then
               istart = itree(ipointer(16)+ibox-1)
               iend = itree(ipointer(17)+ibox-1)
               do i=istart,iend
                  scjsort(i) = rscales(ilev)
               enddo
            endif
         enddo
C$OMP END PARALLEL DO
      enddo


c    initialize legendre function evaluation routines
      nlege = 100
      lw7 = 40000
      call ylgndrfwini(nlege,wlege,lw7,lused7)

c
c
      if(ifprint .ge. 1) 
     $   call prinf('=== STEP 1 (form mp) ====*',i,0)
        time1=second()
C$        time1=omp_get_wtime()
c
c       ... step 1, locate all charges, assign them to boxes, and
c       form multipole expansions


      do ilev=2,nlevels
         if(ifcharge.eq.1.and.ifdipole.eq.0) then
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,npts,istart,iend,nchild)
            do ibox=laddr(1,ilev),laddr(2,ilev)

               istart = itree(ipointer(10)+ibox-1)
               iend = itree(ipointer(11)+ibox-1)
               npts = iend-istart+1

               nchild = itree(ipointer(3)+ibox-1)

               if(npts.gt.0.and.nchild.eq.0) then
                  call l3dformmpc(nd,rscales(ilev),
     1            sourcesort(1,istart),chargesort(1,istart),npts,
     2            centers(1,ibox),nterms(ilev),
     3            rmlexp(iaddr(1,ibox)),wlege,nlege)          
               endif
            enddo
C$OMP END PARALLEL DO          
         endif

         if(ifcharge.eq.0.and.ifdipole.eq.1) then
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,npts,istart,iend,nchild)
            do ibox=laddr(1,ilev),laddr(2,ilev)

               istart = itree(ipointer(10)+ibox-1)
               iend = itree(ipointer(11)+ibox-1)
               npts = iend-istart+1

               nchild = itree(ipointer(3)+ibox-1)

               if(npts.gt.0.and.nchild.eq.0) then
                  call l3dformmpd(nd,rscales(ilev),
     1            sourcesort(1,istart),
     2            dipvecsort(1,1,istart),npts,
     2            centers(1,ibox),nterms(ilev),
     3            rmlexp(iaddr(1,ibox)),wlege,nlege)          
               endif
            enddo
C$OMP END PARALLEL DO          
         endif

         if(ifdipole.eq.1.and.ifcharge.eq.1) then
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,npts,istart,iend,nchild)
            do ibox=laddr(1,ilev),laddr(2,ilev)

               istart = itree(ipointer(10)+ibox-1)
               iend = itree(ipointer(11)+ibox-1)
               npts = iend-istart+1

               nchild = itree(ipointer(3)+ibox-1)

               if(npts.gt.0.and.nchild.eq.0) then
                  call l3dformmpcd(nd,rscales(ilev),
     1            sourcesort(1,istart),chargesort(1,istart),
     2            dipvecsort(1,1,istart),npts,
     2            centers(1,ibox),nterms(ilev),
     3            rmlexp(iaddr(1,ibox)),wlege,nlege)          
               endif
            enddo
C$OMP END PARALLEL DO          
         endif
      enddo



      time2=second()
C$    time2=omp_get_wtime()
      timeinfo(1)=time2-time1



      if(ifprint.ge.1)
     $   call prinf('=== STEP 2 (form lo) ===*',i,0)
      time1=second()
C$    time1=omp_get_wtime()


      if(ifcharge.eq.1.and.ifdipole.eq.0) then
      do ilev=2,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,jbox,nlist4,istart,iend,npts,i)
C$OMP$SCHEDULE(DYNAMIC)
         do ibox=laddr(1,ilev),laddr(2,ilev)
            nlist4 = itree(ipointer(26)+ibox-1)
            do i=1,nlist4
               jbox = itree(ipointer(27)+(ibox-1)*mnlist4+i-1)

c              Form local expansion for all boxes in list3
c              of the current box


               istart = itree(ipointer(10)+jbox-1)
               iend = itree(ipointer(11)+jbox-1)
               npts = iend-istart+1
               if(npts.gt.0) then
                  call l3dformtac(nd,rscales(ilev),
     1             sourcesort(1,istart),chargesort(1,istart),npts,
     2             centers(1,ibox),nterms(ilev),
     3             rmlexp(iaddr(2,ibox)),wlege,nlege)
               endif
            enddo
         enddo
C$OMP END PARALLEL DO
      enddo
      endif


      if(ifcharge.eq.0.and.ifdipole.eq.1) then
      do ilev=2,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,jbox,nlist4,istart,iend,npts,i)
C$OMP$SCHEDULE(DYNAMIC)
         do ibox=laddr(1,ilev),laddr(2,ilev)
            nlist4 = itree(ipointer(26)+ibox-1)
            do i=1,nlist4
               jbox = itree(ipointer(27)+(ibox-1)*mnlist4+i-1)

c              Form local expansion for all boxes in list3
c              of the current box


               istart = itree(ipointer(10)+jbox-1)
               iend = itree(ipointer(11)+jbox-1)
               npts = iend-istart+1
               if(npts.gt.0) then
                   call l3dformtad(nd,rscales(ilev),
     1              sourcesort(1,istart),
     3              dipvecsort(1,1,istart),npts,centers(1,ibox),
     4              nterms(ilev),rmlexp(iaddr(2,ibox)),wlege,nlege)
               endif
            enddo
         enddo
C$OMP END PARALLEL DO         
      enddo
      endif

      if(ifcharge.eq.1.and.ifdipole.eq.1) then
      do ilev=2,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,jbox,nlist4,istart,iend,npts,i)
C$OMP$SCHEDULE(DYNAMIC)
         do ibox=laddr(1,ilev),laddr(2,ilev)
            nlist4 = itree(ipointer(26)+ibox-1)
            do i=1,nlist4
               jbox = itree(ipointer(27)+(ibox-1)*mnlist4+i-1)

c              Form local expansion for all boxes in list3
c              of the current box


               istart = itree(ipointer(10)+jbox-1)
               iend = itree(ipointer(11)+jbox-1)
               npts = iend-istart+1
               if(npts.gt.0) then
                   call l3dformtacd(nd,rscales(ilev),
     1              sourcesort(1,istart),chargesort(1,istart),
     3              dipvecsort(1,1,istart),npts,centers(1,ibox),
     4              nterms(ilev),rmlexp(iaddr(2,ibox)),wlege,nlege)
               endif
            enddo
         enddo
C$OMP END PARALLEL DO         
      enddo
      endif

      time2=second()
C$    time2=omp_get_wtime()
      timeinfo(2)=time2-time1


      lca = 4*nmax


c       
      if(ifprint .ge. 1)
     $      call prinf('=== STEP 3 (merge mp) ====*',i,0)
      time1=second()
C$    time1=omp_get_wtime()
c
      do ilev=nlevels-1,0,-1
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,i,jbox,istart,iend,npts)
         do ibox = laddr(1,ilev),laddr(2,ilev)
            do i=1,8
               jbox = itree(ipointer(4)+8*(ibox-1)+i-1)
               if(jbox.gt.0) then
                  istart = itree(ipointer(10)+jbox-1)
                  iend = itree(ipointer(11)+jbox-1)
                  npts = iend-istart+1
                  if(npts.gt.0) then
                     call l3dmpmp(nd,rscales(ilev+1),
     1               centers(1,jbox),rmlexp(iaddr(1,jbox)),
     2               nterms(ilev+1),rscales(ilev),centers(1,ibox),
     3               rmlexp(iaddr(1,ibox)),nterms(ilev),dc,lca)
                  endif
               endif
            enddo
         enddo
C$OMP END PARALLEL DO         
      enddo

      time2=second()
C$    time2=omp_get_wtime()
      timeinfo(3)=time2-time1

      if(ifprint.ge.1)
     $    call prinf('=== Step 4 (mp to loc) ===*',i,0)
c      ... step 4, convert multipole expansions into local
c       expansions

      time1 = second()
C$        time1=omp_get_wtime()

c
cc     zero out mexp
c 

C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(i,j,k,idim)
      do k=1,6
        do i=1,nboxes
          do j=1,nexptotp
            do idim=1,nd
              mexp(idim,j,i,k) = 0.0d0
            enddo
          enddo
        enddo
      enddo
C$OMP END PARALLEL DO      


      do ilev=2,nlevels

         rscpow(0) = 1.0d0/rscales(ilev)
         rtmp = 1.0d0/rscales(ilev)**2
         do i=1,nterms(ilev)
            rscpow(i) = rscpow(i-1)*rtmp
         enddo

C$OMP PARALLEL DO DEFAULT (SHARED)
C$OMP$PRIVATE(ibox,istart,iend,npts,tmp,mexpf1,mexpf2,mptemp)
         do ibox=laddr(1,ilev),laddr(2,ilev)

            istart = itree(ipointer(10)+ibox-1)
            iend = itree(ipointer(11)+ibox-1)

            npts = iend-istart+1

            if(npts.gt.0) then
c            rescale the multipole expansion

                call mpscale(nd,nterms(ilev),rmlexp(iaddr(1,ibox)),
     1                 rscpow,tmp)
c
cc                process up down for current box
c
                call mpoletoexp(nd,tmp,nterms(ilev),nlams,nfourier,
     1              nexptot,mexpf1,mexpf2,rlsc)

                call ftophys(nd,mexpf1,nlams,rlams,nfourier,nphysical,
     1          nthmax,mexp(1,1,ibox,1),fexpe,fexpo)

                call ftophys(nd,mexpf2,nlams,rlams,nfourier,nphysical,
     1          nthmax,mexp(1,1,ibox,2),fexpe,fexpo)


c
cc                process north-south for current box
c
                call rotztoy(nd,nterms(ilev),tmp,mptemp,rdminus)
                call mpoletoexp(nd,mptemp,nterms(ilev),nlams,nfourier,
     1              nexptot,mexpf1,mexpf2,rlsc)

                call ftophys(nd,mexpf1,nlams,rlams,nfourier,nphysical,
     1          nthmax,mexp(1,1,ibox,3),fexpe,fexpo)

                call ftophys(nd,mexpf2,nlams,rlams,nfourier,nphysical,
     1          nthmax,mexp(1,1,ibox,4),fexpe,fexpo)

c
cc                process east-west for current box

                call rotztox(nd,nterms(ilev),tmp,mptemp,rdplus)
                call mpoletoexp(nd,mptemp,nterms(ilev),nlams,nfourier,
     1              nexptot,mexpf1,mexpf2,rlsc)

                call ftophys(nd,mexpf1,nlams,rlams,nfourier,nphysical,
     1          nthmax,mexp(1,1,ibox,5),fexpe,fexpo)


                call ftophys(nd,mexpf2,nlams,rlams,nfourier,nphysical,
     1          nthmax,mexp(1,1,ibox,6),fexpe,fexpo)

            endif

         enddo
C$OMP END PARALLEL DO         
c
c
cc         loop over parent boxes and ship plane wave
c          expansions to the first child of parent 
c          boxes. 
c          The codes are now written from a gathering perspective
c
c          so the first child of the parent is the one
c          recieving all the local expansions
c          coming from all the lists
c
c          
c
         rscpow(0) = 1.0d0
         rtmp = 1.0d0/rscales(ilev)**2
         do i=1,nterms(ilev)
            rscpow(i) = rscpow(i-1)*rtmp
         enddo
C$OMP PARALLEL DO DEFAULT (SHARED)
C$OMP$PRIVATE(ibox,istart,iend,npts,nchild)
C$OMP$PRIVATE(mexpf1,mexpf2,mexpp1,mexpp2,mexppall)
C$OMP$PRIVATE(nuall,uall,ndall,dall,nnall,nall,nsall,sall)
C$OMP$PRIVATE(neall,eall,nwall,wall,nu1234,u1234,nd5678,d5678)
C$OMP$PRIVATE(nn1256,n1256,ns3478,s3478,ne1357,e1357,nw2468,w2468)
C$OMP$PRIVATE(nn12,n12,nn56,n56,ns34,s34,ns78,s78,ne13,e13,ne57,e57)
C$OMP$PRIVATE(nw24,w24,nw68,w68,ne1,e1,ne3,e3,ne5,e5,ne7,e7)
C$OMP$PRIVATE(nw2,w2,nw4,w4,nw6,w6,nw8,w8)
         do ibox = laddr(1,ilev-1),laddr(2,ilev-1)
           npts = 0
           if(ifpghtarg.gt.0) then
             istart = itree(ipointer(12)+ibox-1)
             iend = itree(ipointer(13)+ibox-1)
             npts = npts + iend-istart+1
           endif

           istart = itree(ipointer(14)+ibox-1)
           iend = itree(ipointer(17)+ibox-1)
           npts = npts + iend-istart+1

           nchild = itree(ipointer(3)+ibox-1)

           if(ifpgh.gt.0) then
             istart = itree(ipointer(10)+ibox-1)
             iend = itree(ipointer(11)+ibox-1)
             npts = npts + iend-istart+1
           endif


           if(npts.gt.0.and.nchild.gt.0) then

               call getpwlistall(ibox,boxsize(ilev),nboxes,
     1         itree(ipointer(18)+ibox-1),itree(ipointer(19)+
     2         mnbors*(ibox-1)),nchild,itree(ipointer(4)),centers,
     3         isep,nuall,uall,ndall,dall,nnall,nall,nsall,sall,neall,
     4         eall,nwall,wall,nu1234,u1234,nd5678,d5678,nn1256,n1256,
     5         ns3478,s3478,ne1357,e1357,nw2468,w2468,nn12,n12,nn56,n56,
     6         ns34,s34,ns78,s78,ne13,e13,ne57,e57,nw24,w24,nw68,w68,
     7         ne1,e1,ne3,e3,ne5,e5,ne7,e7,nw2,w2,nw4,w4,nw6,w6,nw8,w8)

               call processudexp(nd,ibox,ilev,nboxes,centers,
     1         itree(ipointer(4)),rscales(ilev),nterms(ilev),
     2         iaddr,rmlexp,rlams,whts,
     3         nlams,nfourier,nphysical,nthmax,nexptot,nexptotp,mexp,
     4         nuall,uall,nu1234,u1234,ndall,dall,nd5678,d5678,
     5         mexpf1,mexpf2,mexpp1,mexpp2,mexppall(1,1,1),
     6         mexppall(1,1,2),mexppall(1,1,3),mexppall(1,1,4),xshift,
     7         yshift,zshift,fexpback,rlsc,rscpow)
               
               call processnsexp(nd,ibox,ilev,nboxes,centers,
     1         itree(ipointer(4)),rscales(ilev),nterms(ilev),
     2         iaddr,rmlexp,rlams,whts,
     3         nlams,nfourier,nphysical,nthmax,nexptot,nexptotp,mexp,
     4         nnall,nall,nn1256,n1256,nn12,n12,nn56,n56,nsall,sall,
     5         ns3478,s3478,ns34,s34,ns78,s78,
     6         mexpf1,mexpf2,mexpp1,mexpp2,mexppall(1,1,1),
     7         mexppall(1,1,2),mexppall(1,1,3),mexppall(1,1,4),
     8         mexppall(1,1,5),mexppall(1,1,6),mexppall(1,1,7),
     9         mexppall(1,1,8),rdplus,xshift,yshift,zshift,
     9         fexpback,rlsc,rscpow)
               
               call processewexp(nd,ibox,ilev,nboxes,centers,
     1         itree(ipointer(4)),rscales(ilev),nterms(ilev),
     2         iaddr,rmlexp,rlams,whts,
     3         nlams,nfourier,nphysical,nthmax,nexptot,nexptotp,mexp,
     4         neall,eall,ne1357,e1357,ne13,e13,ne57,e57,ne1,e1,
     5         ne3,e3,ne5,e5,ne7,e7,nwall,wall,
     5         nw2468,w2468,nw24,w24,nw68,w68,
     5         nw2,w2,nw4,w4,nw6,w6,nw8,w8,
     6         mexpf1,mexpf2,mexpp1,mexpp2,mexppall(1,1,1),
     7         mexppall(1,1,2),mexppall(1,1,3),mexppall(1,1,4),
     8         mexppall(1,1,5),mexppall(1,1,6),
     8         mexppall(1,1,7),mexppall(1,1,8),mexppall(1,1,9),
     9         mexppall(1,1,10),mexppall(1,1,11),mexppall(1,1,12),
     9         mexppall(1,1,13),mexppall(1,1,14),mexppall(1,1,15),
     9         mexppall(1,1,16),rdminus,xshift,yshift,zshift,
     9         fexpback,rlsc,rscpow)

            endif

         enddo
C$OMP END PARALLEL DO         
      enddo
      time2 = second()
C$        time2=omp_get_wtime()
      timeinfo(4) = time2-time1


      if(ifprint.ge.1)
     $    call prinf('=== Step 5 (split loc) ===*',i,0)

      time1 = second()
C$        time1=omp_get_wtime()
      do ilev = 2,nlevels-1

C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,i,jbox,istart,iend,npts)
         do ibox = laddr(1,ilev),laddr(2,ilev)

            npts = 0

            if(ifpghtarg.gt.0) then
               istart = itree(ipointer(12)+ibox-1)
               iend = itree(ipointer(13)+ibox-1)
               npts = npts + iend-istart+1
            endif

            istart = itree(ipointer(14)+ibox-1)
            iend = itree(ipointer(17)+ibox-1)
            npts = npts + iend-istart+1

            if(ifpgh.gt.0) then
               istart = itree(ipointer(10)+ibox-1)
               iend = itree(ipointer(11)+ibox-1)
               npts = npts + iend-istart+1
            endif

            if(npts.gt.0) then
               do i=1,8
                  jbox = itree(ipointer(4)+8*(ibox-1)+i-1)
                  if(jbox.gt.0) then
                     call l3dlocloc(nd,rscales(ilev),
     1                centers(1,ibox),rmlexp(iaddr(2,ibox)),
     2                nterms(ilev),rscales(ilev+1),centers(1,jbox),
     3                rmlexp(iaddr(2,jbox)),nterms(ilev+1),dc,lca)
                  endif
               enddo
            endif
         enddo
C$OMP END PARALLEL DO         
      enddo
      time2 = second()
C$        time2=omp_get_wtime()
      timeinfo(5) = time2-time1



      if(ifprint.ge.1)
     $    call prinf('=== step 6 (mp eval) ===*',i,0)
      time1 = second()
C$        time1=omp_get_wtime()

   
c
cc       shift mutlipole expansions to expansion center
c        (Note: this part is not relevant for particle codes.
c         It is relevant only for QBX codes)

      do ilev=1,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,nlist3,istart,iend,npts,j,i,jbox)
C$OMP$PRIVATE(mptemp)
C$OMP$SCHEDULE(DYNAMIC)
         do ibox = laddr(1,ilev),laddr(2,ilev)
            nlist3 = itree(ipointer(24)+ibox-1)

            istart = itree(ipointer(16)+ibox-1)
            iend = itree(ipointer(17)+ibox-1)

            do j=istart,iend
               do i=1,nlist3
                  jbox = itree(ipointer(25)+(ibox-1)*mnlist3+i-1)
c
cc                  shift multipole expansion directly from box
c                   center to expansion center
                     call l3dmploc(nd,rscales(ilev+1),
     1               centers(1,jbox),
     1               rmlexp(iaddr(1,jbox)),nterms(ilev+1),
     2               scjsort(j),expcsort(1,j),
     2               tsort(1,0,-ntj,j),ntj,dc,lca)
               enddo
            enddo
         enddo
C$OMP END PARALLEL DO  
      enddo

c
cc       evaluate multipole expansions at source locations
c

      do ilev=1,nlevels
        if(ifpgh.eq.1) then         
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,nlist3,istart,iend,npts,i,jbox)
C$OMP$SCHEDULE(DYNAMIC)
          do ibox=laddr(1,ilev),laddr(2,ilev)
            nlist3 = itree(ipointer(24)+ibox-1)
            istart = itree(ipointer(10)+ibox-1)
            iend = itree(ipointer(11)+ibox-1)

            npts = iend-istart+1

            do i=1,nlist3
              jbox = itree(ipointer(25)+(ibox-1)*mnlist3+i-1)
              call l3dmpevalp(nd,rscales(ilev+1),centers(1,jbox),
     1          rmlexp(iaddr(1,jbox)),nterms(ilev+1),
     2          sourcesort(1,istart),npts,pot(1,istart),wlege,nlege,
     3          thresh)
            enddo
          enddo
C$OMP END PARALLEL DO
        endif

        if(ifpgh.eq.2) then
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,nlist3,istart,iend,npts,i,jbox)
C$OMP$SCHEDULE(DYNAMIC)
          do ibox=laddr(1,ilev),laddr(2,ilev)
            nlist3 = itree(ipointer(24)+ibox-1)
            istart = itree(ipointer(10)+ibox-1)
            iend = itree(ipointer(11)+ibox-1)

            npts = iend-istart+1

            do i=1,nlist3
              jbox = itree(ipointer(25)+(ibox-1)*mnlist3+i-1)
              call l3dmpevalg(nd,rscales(ilev+1),centers(1,jbox),
     1          rmlexp(iaddr(1,jbox)),nterms(ilev+1),
     2          sourcesort(1,istart),npts,pot(1,istart),
     3          grad(1,1,istart),wlege,nlege,thresh)
            enddo
          enddo
C$OMP END PARALLEL DO
        endif

        if(ifpghtarg.eq.1) then         
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,nlist3,istart,iend,npts,i,jbox)
C$OMP$SCHEDULE(DYNAMIC)
          do ibox=laddr(1,ilev),laddr(2,ilev)
            nlist3 = itree(ipointer(24)+ibox-1)
            istart = itree(ipointer(12)+ibox-1)
            iend = itree(ipointer(13)+ibox-1)

            npts = iend-istart+1

            do i=1,nlist3
              jbox = itree(ipointer(25)+(ibox-1)*mnlist3+i-1)
              call l3dmpevalp(nd,rscales(ilev+1),centers(1,jbox),
     1          rmlexp(iaddr(1,jbox)),nterms(ilev+1),
     2          targsort(1,istart),npts,pottarg(1,istart),wlege,nlege,
     3          thresh)
            enddo
          enddo
C$OMP END PARALLEL DO
        endif

        if(ifpghtarg.eq.2) then
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,nlist3,istart,iend,npts,i,jbox)
C$OMP$SCHEDULE(DYNAMIC)
          do ibox=laddr(1,ilev),laddr(2,ilev)
            nlist3 = itree(ipointer(24)+ibox-1)
            istart = itree(ipointer(12)+ibox-1)
            iend = itree(ipointer(13)+ibox-1)

            npts = iend-istart+1

            do i=1,nlist3
              jbox = itree(ipointer(25)+(ibox-1)*mnlist3+i-1)
              call l3dmpevalg(nd,rscales(ilev+1),centers(1,jbox),
     1          rmlexp(iaddr(1,jbox)),nterms(ilev+1),
     2          targsort(1,istart),npts,pottarg(1,istart),
     3          gradtarg(1,1,istart),wlege,nlege,thresh)
            enddo
          enddo
C$OMP END PARALLEL DO
        endif
      enddo


      time2 = second()
C$        time2=omp_get_wtime()
      timeinfo(6) = time2-time1


      if(ifprint.ge.1)
     $    call prinf('=== step 7 (eval lo) ===*',i,0)

c     ... step 7, evaluate all local expansions
c

      time1 = second()
C$        time1=omp_get_wtime()
C

c
cc       shift local expansion to local epxanion at expansion centers
c        (note: this part is not relevant for particle codes.
c        it is relevant only for qbx codes)

      do ilev = 0,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,nchild,istart,iend,i)
C$OMP$SCHEDULE(DYNAMIC)      
         do ibox = laddr(1,ilev),laddr(2,ilev)
            nchild=itree(ipointer(3)+ibox-1)
            if(nchild.eq.0) then 
               istart = itree(ipointer(16)+ibox-1)
               iend = itree(ipointer(17)+ibox-1)
               do i=istart,iend

                  call l3dlocloc(nd,rscales(ilev),
     1             centers(1,ibox),rmlexp(iaddr(2,ibox)),
     2             nterms(ilev),rscales(ilev),expcsort(1,i),
     3             tsort(1,0,-ntj,i),ntj,dc,lca)
               enddo
            endif
         enddo
C$OMP END PARALLEL DO
      enddo

c
cc        evaluate local expansion at source and target
c         locations
c
      do ilev = 0,nlevels
        if(ifpgh.eq.1) then
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,nchild,istart,iend,i,npts)
C$OMP$SCHEDULE(DYNAMIC)      
          do ibox = laddr(1,ilev),laddr(2,ilev)
            nchild=itree(ipointer(3)+ibox-1)
            if(nchild.eq.0) then 
              istart = itree(ipointer(10)+ibox-1)
              iend = itree(ipointer(11)+ibox-1)
              npts = iend-istart+1
              call l3dtaevalp(nd,rscales(ilev),centers(1,ibox),
     1         rmlexp(iaddr(2,ibox)),nterms(ilev),sourcesort(1,istart),
     2         npts,pot(1,istart),wlege,nlege)
            endif
          enddo
C$OMP END PARALLEL DO         
        endif

        if(ifpgh.eq.2) then
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,nchild,istart,iend,i,npts)
C$OMP$SCHEDULE(DYNAMIC)      
          do ibox = laddr(1,ilev),laddr(2,ilev)
            nchild=itree(ipointer(3)+ibox-1)
            if(nchild.eq.0) then 
              istart = itree(ipointer(10)+ibox-1)
              iend = itree(ipointer(11)+ibox-1)
              npts = iend-istart+1
              call l3dtaevalg(nd,rscales(ilev),centers(1,ibox),
     1         rmlexp(iaddr(2,ibox)),nterms(ilev),sourcesort(1,istart),
     2         npts,pot(1,istart),grad(1,1,istart),wlege,nlege)
            endif
          enddo
C$OMP END PARALLEL DO         
        endif

        if(ifpghtarg.eq.1) then
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,nchild,istart,iend,i,npts)
C$OMP$SCHEDULE(DYNAMIC)      
          do ibox = laddr(1,ilev),laddr(2,ilev)
            nchild=itree(ipointer(3)+ibox-1)
            if(nchild.eq.0) then 
              istart = itree(ipointer(12)+ibox-1)
              iend = itree(ipointer(13)+ibox-1)
              npts = iend-istart+1
              call l3dtaevalp(nd,rscales(ilev),centers(1,ibox),
     1         rmlexp(iaddr(2,ibox)),nterms(ilev),targsort(1,istart),
     2         npts,pottarg(1,istart),wlege,nlege)
            endif
          enddo
C$OMP END PARALLEL DO         
        endif

        if(ifpghtarg.eq.2) then
C$OMP PARALLEL DO DEFAULT(SHARED)
C$OMP$PRIVATE(ibox,nchild,istart,iend,i,npts)
C$OMP$SCHEDULE(DYNAMIC)      
          do ibox = laddr(1,ilev),laddr(2,ilev)
            nchild=itree(ipointer(3)+ibox-1)
            if(nchild.eq.0) then 
              istart = itree(ipointer(12)+ibox-1)
              iend = itree(ipointer(13)+ibox-1)
              npts = iend-istart+1

              call l3dtaevalg(nd,rscales(ilev),centers(1,ibox),
     1         rmlexp(iaddr(2,ibox)),nterms(ilev),targsort(1,istart),
     2         npts,pottarg(1,istart),gradtarg(1,1,istart),wlege,nlege)
            endif
          enddo
C$OMP END PARALLEL DO         
        endif
      enddo

    
      time2 = second()
C$        time2=omp_get_wtime()
      timeinfo(7) = time2 - time1


      if(ifprint .ge. 1)
     $     call prinf('=== STEP 8 (direct) =====*',i,0)
      time1=second()
C$        time1=omp_get_wtime()

c
cc       directly form local expansions for list1 sources
c        at expansion centers. 
c        (note: this part is not relevant for particle codes.
c         It is relevant only for qbx codes)


      do ilev=0,nlevels
C$OMP PARALLEL DO DEFAULT(SHARED)     
C$OMP$PRIVATE(ibox,istarte,iende,nlist1,i,jbox)
C$OMP$PRIVATE(jstart,jend)
         do ibox = laddr(1,ilev),laddr(2,ilev)
            istarte = itree(ipointer(16)+ibox-1)
            iende = itree(ipointer(17)+ibox-1)

            nlist1 = itree(ipointer(20)+ibox-1)

            do i =1,nlist1
               jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)


               jstart = itree(ipointer(10)+jbox-1)
               jend = itree(ipointer(11)+jbox-1)

cc               call prinf('nexpc=*',nexpc,1)

               call lfmm3dexpc_direct(nd,jstart,jend,istarte,
     1         iende,sourcesort,ifcharge,chargesort,ifdipole,
     2         dipvecsort,expcsort,tsort,scjsort,ntj,
     3         wlege,nlege)
            enddo
         enddo
C$OMP END PARALLEL DO
      enddo

c
cc        directly evaluate potential at sources and targets 
c         due to sources in list1

      do ilev=0,nlevels
c
cc           evaluate at the sources
c

        if(ifpgh.eq.1) then
          if(ifcharge.eq.1.and.ifdipole.eq.0) then
C$OMP PARALLEL DO DEFAULT(SHARED)     
C$OMP$PRIVATE(ibox,istarts,iends,npts0,nlist1,i,jbox,jstart,jend,npts)
C$OMP$SCHEDULE(DYNAMIC)      
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istarts = itree(ipointer(10)+ibox-1)
              iends = itree(ipointer(11)+ibox-1)
              npts0 = iends-istarts+1
              nlist1 = itree(ipointer(20)+ibox-1)

              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call l3ddirectcp(nd,sourcesort(1,jstart),
     1             chargesort(1,jstart),npts,sourcesort(1,istarts),
     2             npts0,pot(1,istarts),thresh)          
              enddo
            enddo
C$OMP END PARALLEL DO     
          endif

          if(ifcharge.eq.0.and.ifdipole.eq.1) then
C$OMP PARALLEL DO DEFAULT(SHARED)     
C$OMP$PRIVATE(ibox,istarts,iends,npts0,nlist1,i,jbox,jstart,jend,npts)
C$OMP$SCHEDULE(DYNAMIC)      
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istarts = itree(ipointer(10)+ibox-1)
              iends = itree(ipointer(11)+ibox-1)
              npts0 = iends-istarts+1
              nlist1 = itree(ipointer(20)+ibox-1)
              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call l3ddirectdp(nd,sourcesort(1,jstart),
     2             dipvecsort(1,1,jstart),npts,sourcesort(1,istarts),
     2             npts0,pot(1,istarts),thresh)          
              enddo
            enddo
C$OMP END PARALLEL DO     
          endif

          if(ifcharge.eq.1.and.ifdipole.eq.1) then
C$OMP PARALLEL DO DEFAULT(SHARED)     
C$OMP$PRIVATE(ibox,istarts,iends,npts0,nlist1,i,jbox,jstart,jend,npts)
C$OMP$SCHEDULE(DYNAMIC)      
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istarts = itree(ipointer(10)+ibox-1)
              iends = itree(ipointer(11)+ibox-1)
              npts0 = iends-istarts+1
              nlist1 = itree(ipointer(20)+ibox-1)
              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call l3ddirectcdp(nd,sourcesort(1,jstart),
     1             chargesort(1,jstart),
     2             dipvecsort(1,1,jstart),npts,sourcesort(1,istarts),
     2             npts0,pot(1,istarts),thresh)          
              enddo
            enddo
C$OMP END PARALLEL DO     
          endif
        endif

        if(ifpgh.eq.2) then
          if(ifcharge.eq.1.and.ifdipole.eq.0) then
C$OMP PARALLEL DO DEFAULT(SHARED)     
C$OMP$PRIVATE(ibox,istarts,iends,npts0,nlist1,i,jbox,jstart,jend,npts)
C$OMP$SCHEDULE(DYNAMIC)      
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istarts = itree(ipointer(10)+ibox-1)
              iends = itree(ipointer(11)+ibox-1)
              npts0 = iends-istarts+1
              nlist1 = itree(ipointer(20)+ibox-1)

              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call l3ddirectcg(nd,sourcesort(1,jstart),
     1             chargesort(1,jstart),npts,sourcesort(1,istarts),
     2             npts0,pot(1,istarts),grad(1,1,istarts),thresh)   
              enddo
            enddo
C$OMP END PARALLEL DO     
          endif

          if(ifcharge.eq.0.and.ifdipole.eq.1) then

C$OMP PARALLEL DO DEFAULT(SHARED)     
C$OMP$PRIVATE(ibox,istarts,iends,npts0,nlist1,i,jbox,jstart,jend,npts)
C$OMP$SCHEDULE(DYNAMIC)      
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istarts = itree(ipointer(10)+ibox-1)
              iends = itree(ipointer(11)+ibox-1)
              npts0 = iends-istarts+1
              nlist1 = itree(ipointer(20)+ibox-1)
              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call l3ddirectdg(nd,sourcesort(1,jstart),
     2             dipvecsort(1,1,jstart),npts,sourcesort(1,istarts),
     2             npts0,pot(1,istarts),grad(1,1,istarts),thresh)          
              enddo
            enddo
C$OMP END PARALLEL DO     
          endif

          if(ifcharge.eq.1.and.ifdipole.eq.1) then

C$OMP PARALLEL DO DEFAULT(SHARED)     
C$OMP$PRIVATE(ibox,istarts,iends,npts0,nlist1,i,jbox,jstart,jend,npts)
C$OMP$SCHEDULE(DYNAMIC)      
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istarts = itree(ipointer(10)+ibox-1)
              iends = itree(ipointer(11)+ibox-1)
              npts0 = iends-istarts+1
              nlist1 = itree(ipointer(20)+ibox-1)
              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call l3ddirectcdg(nd,sourcesort(1,jstart),
     1             chargesort(1,jstart),
     2             dipvecsort(1,1,jstart),npts,sourcesort(1,istarts),
     2             npts0,pot(1,istarts),grad(1,1,istarts),thresh)          
              enddo
            enddo
C$OMP END PARALLEL DO     
          endif
        endif

        if(ifpghtarg.eq.1) then
          if(ifcharge.eq.1.and.ifdipole.eq.0) then
C$OMP PARALLEL DO DEFAULT(SHARED)     
C$OMP$PRIVATE(ibox,istartt,iendt,npts0,nlist1,i,jbox,jstart,jend,npts)
C$OMP$SCHEDULE(DYNAMIC)      
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istartt = itree(ipointer(12)+ibox-1)
              iendt = itree(ipointer(13)+ibox-1)
              npts0 = iendt-istartt+1
              nlist1 = itree(ipointer(20)+ibox-1)

              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call l3ddirectcp(nd,sourcesort(1,jstart),
     1             chargesort(1,jstart),npts,targsort(1,istartt),
     2             npts0,pottarg(1,istartt),thresh)          
              enddo
            enddo
C$OMP END PARALLEL DO     
          endif

          if(ifcharge.eq.0.and.ifdipole.eq.1) then
C$OMP PARALLEL DO DEFAULT(SHARED)     
C$OMP$PRIVATE(ibox,istartt,iendt,npts0,nlist1,i,jbox,jstart,jend,npts)
C$OMP$SCHEDULE(DYNAMIC)      
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istartt = itree(ipointer(12)+ibox-1)
              iendt = itree(ipointer(13)+ibox-1)
              npts0 = iendt-istartt+1
              nlist1 = itree(ipointer(20)+ibox-1)
              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call l3ddirectdp(nd,sourcesort(1,jstart),
     2             dipvecsort(1,1,jstart),npts,targsort(1,istartt),
     2             npts0,pottarg(1,istartt),thresh)          
              enddo
            enddo
C$OMP END PARALLEL DO     
          endif

          if(ifcharge.eq.1.and.ifdipole.eq.1) then
C$OMP PARALLEL DO DEFAULT(SHARED)     
C$OMP$PRIVATE(ibox,istartt,iendt,npts0,nlist1,i,jbox,jstart,jend,npts)
C$OMP$SCHEDULE(DYNAMIC)      
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istartt = itree(ipointer(12)+ibox-1)
              iendt = itree(ipointer(13)+ibox-1)
              npts0 = iendt-istartt+1
              nlist1 = itree(ipointer(20)+ibox-1)
              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call l3ddirectcdp(nd,sourcesort(1,jstart),
     1             chargesort(1,jstart),
     2             dipvecsort(1,1,jstart),npts,targsort(1,istartt),
     2             npts0,pottarg(1,istartt),thresh)          
              enddo
            enddo
C$OMP END PARALLEL DO     
          endif
        endif

        if(ifpghtarg.eq.2) then
          if(ifcharge.eq.1.and.ifdipole.eq.0) then
C$OMP PARALLEL DO DEFAULT(SHARED)     
C$OMP$PRIVATE(ibox,istartt,iendt,npts0,nlist1,i,jbox,jstart,jend,npts)
C$OMP$SCHEDULE(DYNAMIC)      
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istartt = itree(ipointer(12)+ibox-1)
              iendt = itree(ipointer(13)+ibox-1)
              npts0 = iendt-istartt+1
              nlist1 = itree(ipointer(20)+ibox-1)

              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call l3ddirectcg(nd,sourcesort(1,jstart),
     1             chargesort(1,jstart),npts,targsort(1,istartt),
     2             npts0,pottarg(1,istartt),gradtarg(1,1,istartt),
     3             thresh)   
              enddo
            enddo
C$OMP END PARALLEL DO     
          endif

          if(ifcharge.eq.0.and.ifdipole.eq.1) then
C$OMP PARALLEL DO DEFAULT(SHARED)     
C$OMP$PRIVATE(ibox,istartt,iendt,npts0,nlist1,i,jbox,jstart,jend,npts)
C$OMP$SCHEDULE(DYNAMIC)      
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istartt = itree(ipointer(12)+ibox-1)
              iendt = itree(ipointer(13)+ibox-1)
              npts0 = iendt-istartt+1
              nlist1 = itree(ipointer(20)+ibox-1)
              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call l3ddirectdg(nd,sourcesort(1,jstart),
     2             dipvecsort(1,1,jstart),npts,targsort(1,istartt),
     2             npts0,pottarg(1,istartt),gradtarg(1,1,istartt),
     3             thresh)          
              enddo
            enddo
C$OMP END PARALLEL DO     
          endif

          if(ifcharge.eq.1.and.ifdipole.eq.1) then
C$OMP PARALLEL DO DEFAULT(SHARED)     
C$OMP$PRIVATE(ibox,istartt,iendt,npts0,nlist1,i,jbox,jstart,jend,npts)
C$OMP$SCHEDULE(DYNAMIC)      
            do ibox = laddr(1,ilev),laddr(2,ilev)
              istartt = itree(ipointer(12)+ibox-1)
              iendt = itree(ipointer(13)+ibox-1)
              npts0 = iendt-istartt+1
              nlist1 = itree(ipointer(20)+ibox-1)
              do i=1,nlist1
                jbox = itree(ipointer(21)+mnlist1*(ibox-1)+i-1)
                jstart = itree(ipointer(10)+jbox-1)
                jend = itree(ipointer(11)+jbox-1)
                npts = jend-jstart+1
                call l3ddirectcdg(nd,sourcesort(1,jstart),
     1             chargesort(1,jstart),
     2             dipvecsort(1,1,jstart),npts,targsort(1,istartt),
     2             npts0,pottarg(1,istartt),gradtarg(1,1,istartt),
     3             thresh)          
              enddo
            enddo
C$OMP END PARALLEL DO     
          endif
        endif
      enddo
 
      time2 = second()
C$        time2=omp_get_wtime()
      timeinfo(8) = time2-time1
      if(ifprint.ge.1) call prin2('timeinfo=*',timeinfo,8)
      d = 0
      do i = 1,8
         d = d + timeinfo(i)
      enddo

      if(ifprint.ge.1) call prin2('sum(timeinfo)=*',d,1)

      return
      end
c------------------------------------------------
      subroutine lfmm3dexpc_direct(nd,istart,iend,jstart,jend,
     $     source,ifcharge,charge,ifdipole,
     $     dipvec,expc,texps,scj,ntj,wlege,nlege)
c--------------------------------------------------------------------
c     This subroutine adds the local expansions due to sources
c     istart to iend in the source array at the expansion centers
c     jstart to jend in the expansion center array to the existing 
c     local expansions at the corresponding expansion centers.
c
c     INPUT arguments
c-------------------------------------------------------------------
c     nd           in: integer
c                  number of charge densities
c
c     istart       in:Integer
c                  Starting index in source array whose expansions
c                  we wish to add
c
c     iend         in:Integer
c                  Last index in source array whose expansions
c                  we wish to add
c
c     jstart       in: Integer
c                  First index in the expansion center array at 
c                  which we  wish to compute the expansions
c 
c     jend         in:Integer
c                  Last index in expansion center array at 
c                  which we wish to compute the expansions
c 
c     scjsort      in: double precision(*)
c                  Scale of expansions formed at the expansion centers
c
c     source       in: double precision(3,ns)
c                  Source locations
c
c     ifcharge     in: Integer
c                  flag for including expansions due to charges
c                  The expansion due to charges will be included
c                  if ifcharge == 1
c
c     charge       in: double precision
c                  Charge at the source locations
c
c     ifdipole     in: Integer
c                 flag for including expansions due to dipoles
c                 The expansion due to dipoles will be included
c                 if ifdipole == 1
c
c     dipvec      in: double precision(3,ns)
c                 Dipole orientation vector at the source locations
c
c     expc        in: double precision(3,nexpc)
c                 Expansion center locations
c
c     ntj         in: Integer
c                 Number of terms in expansion
c
c     wlege       in: double precision(0:nlege,0:nlege)
c                 precomputed array of recurrence relation
c                 coeffs for Ynm calculation.
c
c    nlege        in: integer
c                 dimension parameter for wlege
c------------------------------------------------------------
c     OUTPUT
c
c   Updated expansions at the targs
c   texps       out: double complex(0:ntj,-ntj:ntj,expc) 
c                 coeffs for local expansions
c-------------------------------------------------------               
        implicit none
c
        integer istart,iend,jstart,jend,ns,j, nlege
        integer ifcharge,ifdipole,ier,nd
        double precision source(3,*)
        double precision scj(*)
        double precision wlege(*)
        double precision charge(nd,*)
        double precision dipvec(nd,3,*)
        double precision expc(3,*)

        integer nlevels,ntj
c
        double complex texps(nd,0:ntj,-ntj:ntj,*)
        
c
        ns = iend - istart + 1
        if(ifcharge.eq.1.and.ifdipole.eq.0) then
          do j=jstart,jend
            call l3dformtac(nd,scj(j),
     1        source(1,istart),charge(1,istart),ns,
     2        expc(1,j),ntj,texps(1,0,-ntj,j),wlege,nlege)
           enddo
         endif

         if(ifcharge.eq.0.and.ifdipole.eq.1) then
          do j=jstart,jend
            call l3dformtad(nd,scj(j),
     1        source(1,istart),
     2        dipvec(1,1,istart),ns,expc(1,j),ntj,texps(1,0,-ntj,j),
     3        wlege,nlege)
           enddo
         endif

         if(ifcharge.eq.1.and.ifdipole.eq.1) then
          do j=jstart,jend
            call l3dformtacd(nd,scj(j),
     1        source(1,istart),charge(1,istart),
     2        dipvec(1,1,istart),ns,expc(1,j),ntj,texps(1,0,-ntj,j),
     3        wlege,nlege)
           enddo
         endif

c
        return
        end