
EXEC = int2

HOST=macosx
#HOST = linux-gfortran
#HOST= linux-gfortran-openmp
#HOST = linux-ifort

ifeq ($(HOST),macosx)
FC = gfortran
FFLAGS = -O3 -c -w -march=native -finteger-4-integer-8 -fdefault-integer-8 
#FFLAGS = -O3 -c -w -march=native 
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

OBJ_DIR = ../../build


vpath %.f = .:../../src:../../src/Laplace:../../src/Common

.PHONY: all clean list

SOURCES =  test_lfmm3d.f \
  tree_lr_3d.f \
  dlaran.f \
  hkrand.f \
  prini.f \
  rotgen.f \
  legeexps.f \
  rotviarecur.f \
  yrecursion.f \
  l3dterms.f \
  l3dtrans.f \
  laprouts3d.f \
  lfmm3d.f \
  lfmm3dwrap.f \
  lpwrouts.f \
  lwtsexp_sep1.f \
  lwtsexp_sep2.f \
  fmmcommon.f \
  rotproj.f \
  dfft.f \


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



