
EXEC = int2

#HOST=macosx
HOST = linux-gfortran
#HOST= linux-gfortran-openmp
#HOST = linux-ifort

ifeq ($(HOST),macosx)
FC = gfortran
FFLAGS = -O3 -c -w -march=native -pg 
FLINK = gfortran -w -o $(EXEC)
FEND =  
endif

ifeq ($(HOST),linux-gfortran-openmp)
				
FC = gfortran
FFLAGS = -O3 -c -w --openmp 
FLINK = gfortran -w -o $(EXEC) --openmp

endif

ifeq ($(HOST),linux-gfortran)
				
FC = gfortran
FFLAGS = -O3 -c -w  -march=native -pg -ffast-math -ftree-vectorize -funroll-loops
FLINK = gfortran -w -o $(EXEC) -pg 

endif

ifeq ($(HOST),linux-ifort)
				
FC = ifort
FFLAGS = -O3 -c -w  -xW -ip -xHost
FLINK = ifort -w -o $(EXEC)

endif


SRC = ../src
LAP = ../src/Laplace
COM = ../src/Common
TREE = ../../../TreeCodes
OBJ_DIR = ../build


vpath %.f = .:../src:../src/Laplace:../src/Common

.PHONY: all clean list

SOURCES =  lfmm3dstot_dr.f \
  d3hplratree.f \
  dlaran.f \
  hkrand.f \
  prini.f \
  rotgen.f \
  rotgen2.f \
  legeexps.f \
  rotviarecur3.f \
  yrecursion.f \
  l3dterms.f \
  l3dtrans.f \
  laprouts3d.f \
  lfmm3dpart.f \
  lpwrouts.f \
  lwtsexp_sep1.f \
  lwtsexp_sep2.f \
  fmmcommon.f \

OBJECTS = $(patsubst %.f,$(OBJ_DIR)/%.o,$(SOURCES))

#
# use only the file part of the filename, then manually specify
# the build location
#

$(OBJ_DIR)/%.o : %.f
	$(FC) $(FFLAGS) $< -o $@

all: $(OBJECTS)
	rm -f $(EXEC)
	$(FLINK) $(OBJECTS) $(FEND)
	./$(EXEC)

clean:
	rm -f $(OBJECTS)
	rm -f $(EXEC)

list: $(SOURCES)
	$(warning Requires:  $^)


