########################################################
# Configuration variables

PYTHON ?= python3
PYVENV ?= .venv
STIMULUS ?= $(PYVENV)/bin/stimulus

all: build

########################################################
# Main package

top_srcdir=cigraph
VERSION=$(shell tools/getversion.sh)

# We put the version number in a file, so that we can detect
# if it changes

version_number: force
	@echo '$(VERSION)' | cmp -s - $@ || echo '$(VERSION)' > $@

# Source files from the C library
CORESRC := $(shell cd $(top_srcdir) ; git ls-files --full-name src | \
	      grep -v '\.txt$$' | grep -v "COPYING$$" | grep -v "README" | \
		  grep -v "src/config.h.in" )

# Vendored dependencies of the C library. We don't need BLAS / LAPACK
# because they are included in R. We don't need F2C either because we
# will use the original Fortran sources for ARPACK. We also rely on an
# external GLPK instead of the one vendored in igraph because the
# vendored GLPK does not fit well in the build process of the R interface.
VENDORSRC := $(shell cd $(top_srcdir) ; git ls-files --full-name vendor | \
	      grep -v "^vendor/lapack/" | grep -v "^vendor/f2c" | \
	      grep -v "^vendor/glpk/" | \
	      grep -v '\.txt$$' | grep -v "COPYING$$" | grep -v "README" )

# Include files from the C library
CINC := $(shell cd $(top_srcdir) ; git ls-files --full-name include)
CINC := $(patsubst include/%, src/include/%, $(CINC))

# Transform CORESRC and VENDORSRC to their target folders in src/
CORESRC := $(patsubst src/%, src/core/%, $(CORESRC))
VENDORSRC := $(patsubst vendor/%, src/vendor/%, $(VENDORSRC))

# Rules that copy the sources from cigraph/ to src/
$(CORESRC): src/core/%: $(top_srcdir)/src/%
	mkdir -p $(@D) && cp $< $@
$(VENDORSRC): src/vendor/%: $(top_srcdir)/vendor/%
	mkdir -p $(@D) && cp $< $@
$(CINC): src/include/%: $(top_srcdir)/include/%
	mkdir -p $(@D) && cp $< $@

# Files generated by flex/bison

PARSER := $(shell cd $(top_srcdir) ; git ls-files --full-name src | \
	    grep -E '\.(l|y)$$')
PARSER1 := $(patsubst src/%.l, src/core/%.c, $(PARSER))
PARSER2 := $(patsubst src/%.y, src/core/%.c, $(PARSER1))

YACC=bison -b yy -d
LEX=flex

%.c: %.y
	$(YACC) $<
	mv -f yy.tab.c $@
	mv -f yy.tab.h $(@:.c=.h)

%.c: %.l
	$(LEX) -o $@ --header-file=$(@:.c=.h) $<

# Create Python virtualenv for Stimulus

venv: $(PYVENV)/stamp

$(PYVENV)/stamp: tools/build-requirements.txt
	$(PYTHON) -m venv $(PYVENV)
	$(PYVENV)/bin/pip install -r $<
	touch $(PYVENV)/stamp

# Apply possible patches

patches: $(CORESRC) $(VENDORSRC) $(CINC) $(PARSER2)
	if [ -d "patches" ]; then \
		find patches -type f -name '*.patch' -print0 | sort -z | xargs -t -0 -n 1 tools/apply-patch.sh; \
	fi
	-rm -f src/*.orig
	tools/fix-lexers.sh

# C files generated by C configure

CGEN = src/include/igraph_export.h src/include/igraph_threading.h src/include/igraph_version.h

src/include/igraph_export.h: tools/stimulus/igraph_export.h
	mkdir -p src/include
	cp $< $@

src/include/igraph_threading.h: $(top_srcdir)/include/igraph_threading.h.in
	mkdir -p src
	sed 's/#cmakedefine01 IGRAPH_THREAD_SAFE/#define IGRAPH_THREAD_SAFE 0/g' $< >$@

src/include/igraph_version.h: $(top_srcdir)/include/igraph_version.h.in
	mkdir -p src
	# Don't use ${VERSION} here in the replacement; this would mean that the
	# replacement would be done _now_ and not at compile time where we pass
	# -DPACKAGE_VERSION=... to the compiler
	sed 's/"@PACKAGE_VERSION@"/PACKAGE_VERSION/g' $< >$@

# R source and doc files

RSRC := $(shell git ls-files R doc inst demo NEWS cleanup.win configure.win)

# ARPACK Fortran sources

ARPACK := $(shell git ls-files vendor/arpack)
ARPACK2 := $(patsubst vendor/arpack/%, src/vendor/arpack/%, $(ARPACK))

$(ARPACK2): src/vendor/arpack/%: vendor/arpack/%
	mkdir -p $(@D) && cp $< $@

# libuuid

UUID := $(shell git ls-files vendor/uuid)
UUID2 := $(patsubst vendor/uuid/%, src/vendor/uuid/%, $(UUID))

$(UUID2): src/vendor/uuid/%: vendor/uuid/%
	mkdir -p $(@D) && cp $< $@

# Simpleraytracer

RAY := $(shell git ls-files vendor/simpleraytracer)
RAY2 := $(patsubst vendor/simpleraytracer/%, src/vendor/simpleraytracer/%, $(RAY))

$(RAY2): src/vendor/%: vendor/%
	mkdir -p $(@D) && cp $< $@

# R files that are generated/copied

RGEN = R/aaa-auto.R src/rinterface.c src/rinterface.h src/rrandom.c src/rrandom.h \
	src/rinterface_extra.c src/lazyeval.c src/init.c src/igraph-win.def \
	src/Makevars.in configure src/config.h.in src/Makevars.win src/Makevars.ucrt \
	DESCRIPTION

# Files generated by stimulus

src/rinterface.c: \
		$(top_srcdir)/interfaces/functions.yaml \
		$(top_srcdir)/interfaces/types.yaml \
		tools/stimulus/rinterface.c.in  \
		tools/stimulus/functions-R.yaml \
		tools/stimulus/types-RC.yaml
	$(STIMULUS) \
           -f $(top_srcdir)/interfaces/functions.yaml \
           -f tools/stimulus/functions-R.yaml \
           -i tools/stimulus/rinterface.c.in \
           -o src/rinterface.c \
           -t $(top_srcdir)/interfaces/types.yaml \
           -t tools/stimulus/types-RC.yaml \
           -l RC

src/init.c: \
		$(top_srcdir)/interfaces/functions.yaml \
		$(top_srcdir)/interfaces/types.yaml \
		tools/stimulus/init.c.in  \
		tools/stimulus/functions-R.yaml \
		tools/stimulus/types-RR.yaml
	$(STIMULUS) \
           -f $(top_srcdir)/interfaces/functions.yaml \
           -f tools/stimulus/functions-R.yaml \
           -i tools/stimulus/init.c.in \
           -o src/init.c \
           -t $(top_srcdir)/interfaces/types.yaml \
           -t tools/stimulus/types-RR.yaml \
           -l RInit

R/aaa-auto.R: \
		$(top_srcdir)/interfaces/functions.yaml \
		$(top_srcdir)/interfaces/types.yaml \
		tools/stimulus/aaa-auto.R.in \
		tools/stimulus/functions-R.yaml \
		tools/stimulus/types-RR.yaml
	$(STIMULUS) \
           -f $(top_srcdir)/interfaces/functions.yaml \
           -f tools/stimulus/functions-R.yaml \
           -i tools/stimulus/aaa-auto.R.in \
           -o R/aaa-auto.R \
           -t $(top_srcdir)/interfaces/types.yaml \
           -t tools/stimulus/types-RR.yaml \
           -l RR

# configure files

configure src/config.h.in: configure.ac
	autoheader; autoconf
	# CMake needs HAVE_ISFINITE but configure.ac generates HAVE_DECL_ISFINITE
	echo "#define HAVE_ISFINITE HAVE_DECL_ISFINITE" >>src/config.h.in

# DESCRIPTION file, we re-generate it only if the VERSION number
# changes or $< changes

DESCRIPTION: tools/stimulus/DESCRIPTION version_number
	sed 's/^Version: .*$$/Version: '$(VERSION)'/' $< > $@

src/%.h: tools/stimulus/%.h
	mkdir -p src
	cp $< $@

src/rinterface_extra.c: tools/stimulus/rinterface_extra.c
	mkdir -p src
	cp $< $@

src/lazyeval.c: tools/stimulus/lazyeval.c
	mkdir -p src
	cp $< $@

src/rrandom.c: tools/stimulus/rrandom.c
	mkdir -p src
	cp $< $@

src/igraph-win.def: tools/stimulus/igraph-win.def
	mkdir -p src
	cp $< $@

# This is the list of all object files in the R package,
# we write it to a file to be able to depend on it.
# Makevars.in, Makevars.win and Makevars.ucrt are only regenerated if
# the list of object files changes.

OBJECTS := $(shell echo $(CORESRC) $(VENDORSRC) $(ARPACK) $(RAY) $(UUID) | \
		tr ' ' '\n' | \
        grep -E '\.(c|cpp|cc|f|l|y)$$' | \
		sed 's/\.[^\.][^\.]*$$/.o/' | \
		sed 's,^src/,,' \
		) rinterface.o rinterface_extra.o rrandom.o lazyeval.o

object_files: force
	@echo '$(OBJECTS)' | cmp -s - $@ || echo '$(OBJECTS)' > $@

configure.ac: %: tools/stimulus/%
	sed 's/@VERSION@/'$(VERSION)'/g' $< >$@

src/Makevars.win src/Makevars.ucrt src/Makevars.in: src/%: tools/stimulus/% \
		object_files
	sed 's/@VERSION@/'$(VERSION)'/g' $< >$@
	printf "%s" "OBJECTS=" >> $@
	sed 's/ / \\\n/g' object_files >> $@

pre_build: venv patches $(CSRC) $(CINC2) $(PARSER2) $(RSRC) $(RGEN) \
	$(CGEN) $(RAY2) $(ARPACK2) $(UUID2)

# We have everything, here we go

build: pre_build
	if ! [ -f src/Makevars ]; then ./configure; fi
	R CMD INSTALL -l "/tmp" --no-configure --no-byte-compile .

igraph: igraph_$(VERSION).tar.gz

igraph_$(VERSION).tar.gz: pre_build
	rm -f src/config.h
	rm -f src/Makevars
	touch src/config.h
	mkdir -p man
	tools/builddocs.sh
	Rscript -e 'devtools::build(path = ".")'

#############

check: igraph_$(VERSION).tar.gz
	_R_CHECK_FORCE_SUGGESTS_=0 R CMD check $<

check-cran: igraph_$(VERSION).tar.gz
	_R_CHECK_FORCE_SUGGESTS_=0 R CMD check --as-cran $<

check-links: igraph_$(VERSION).tar.gz
	mkdir -p html-docs
	R CMD INSTALL --html --no-R --no-configure --no-inst --no-libs --no-exec --no-test-load -l html-docs $<
	$(PYVENV)/bin/linkchecker html-docs/igraph/html/00Index.html ; rm -rf html-docs

check-rhub: igraph
	Rscript -e 'rhub::check_for_cran()'

check-revdeps: igraph
	Rscript -e 'options(width=204); revdepcheck::revdep_check(num_workers=8, quiet=F, bioc=F)'

install:
	Rscript -e 'devtools::install(".")'

test:
	Rscript -e 'devtools::test(".")'

clean:
	@rm -f  DESCRIPTION
	@rm -f  R/aaa-auto.R
	@rm -rf autom4te.cache/
	@rm -f  config.log
	@rm -f  config.status
	@rm -f  configure
	@rm -f  igraph_*.tar.gz
	@rm -f  igraph_*.tgz
	@rm -rf man/*.Rd
	@rm -f  object_files
	@rm -rf src/
	@rm -rf version_number
	@rm -f  configure.ac
	@cd $(top_srcdir) && git reset --hard

distclean: clean
	@rm -rf $(PYVENV)

.PHONY: all igraph force clean check check-cran check-rhub check-links install test

.NOTPARALLEL:
