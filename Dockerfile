# syntax=docker/dockerfile:1
#
# Multi-stage Dockerfile for ACL2 on SBCL.
#
# This file has three final build targets, selected with --target:
#
#   runtime    - Lean image: SBCL + ACL2 + books as source (not certified).
#                Built for linux/amd64 and linux/arm64 by
#                .github/workflows/docker-multiplatform-selfhosted.yml
#
#   kcerts     - Medium image: everything in 'runtime', plus the
#                STP and Z3 solvers, with all the books reachable from
#                kestrel/top certified.
#                Built for linux/amd64 and linux/arm64 by
#                .github/workflows/docker-kcerts-selfhosted.yml
#
#   allcerts   - Large linux/amd64 image: everything in 'kcerts', plus the
#                rest of the books of the standard "make regression" suite
#                certified.  Built by
#                .github/workflows/docker-allcerts-selfhosted.yml
#
# ('kcerts' builds on the intermediate 'cert-base' stage, which adds the
# solvers and a common certify-and-clean script, and 'allcerts' builds on
# 'kcerts': its regression skips the already-certified kestrel books and
# certifies the rest.  This layering means an allcerts build produces the
# (linux/amd64) kcerts image along the way, the two images share their
# kestrel layers, and the allcerts certification artifacts are split across
# two layers instead of one very large one.)
#
# IMPORTANT: 'allcerts' is the last stage in this file, so a plain
# "docker build ." with no --target builds the allcerts image, which runs a
# full book regression and can take hours.  For the lean image, build with:
#   docker build --target runtime .
#
# =============================================================================
# SBCL VERSION CONFIGURATION
# =============================================================================
# To update SBCL version, change BOTH of these values together.
# To compute SHA256: curl -fsSL "<url>" | shasum -a 256
#
ARG SBCL_VERSION=2.6.1
ARG SBCL_SHA256=5f2cd5bb7d3e6d9149a59c05acd8429b3be1849211769e5a37451d001e196d7f
# =============================================================================
#
# Other build arguments:
#   ACL2_COMMIT       - ACL2 commit/tag/branch to build (default: master)
#   ACL2_BUILD_TYPE   - "master" or "commit" (see acl2-builder stage)
#
# Build arguments used only by the 'kcerts' and 'allcerts' targets:
#   STP_VERSION       - STP release tag to build from source
#   MINISAT_COMMIT    - commit of STP's minisat fork (STP build dependency)
#   Z3_SOLVER_VERSION - version of the z3-solver PyPI package, which provides
#                       both the z3 executable and the Python bindings that
#                       Smtlink uses
#   CERT_JOBS         - parallel book certification jobs (default: nproc)

# =============================================================================
# Stage 1: Build SBCL from source
# =============================================================================
FROM ubuntu:24.04 AS sbcl-builder

# Import ARGs and persist as ENV for use throughout this stage
ARG SBCL_VERSION
ARG SBCL_SHA256
ENV SBCL_VERSION=${SBCL_VERSION}
ENV SBCL_SHA256=${SBCL_SHA256}

# Install bootstrap SBCL from apt (works for both amd64 and arm64)
# plus build dependencies
# libzstd-dev is required for --fancy flag (zstd core compression)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    ca-certificates \
    zlib1g-dev \
    libzstd-dev \
    bzip2 \
    sbcl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Download SBCL source and verify checksum
# (If version and SHA256 don't match, this will fail)
RUN echo "Downloading SBCL ${SBCL_VERSION}..." && \
    curl -fsSL "https://downloads.sourceforge.net/project/sbcl/sbcl/${SBCL_VERSION}/sbcl-${SBCL_VERSION}-source.tar.bz2" \
    -o sbcl-source.tar.bz2 && \
    echo "Verifying SHA256: ${SBCL_SHA256}" && \
    echo "${SBCL_SHA256}  sbcl-source.tar.bz2" | sha256sum -c - && \
    tar xjf sbcl-source.tar.bz2 && \
    rm sbcl-source.tar.bz2

# Build SBCL with ACL2-recommended switches
# See ACL2 xdoc topic SBCL-INSTALLATION for details
# --fancy enables core compression (requires libzstd-dev) and other optional features
# --dynamic-space-size=4Gb is sufficient for building ACL2; users can increase at runtime
WORKDIR /build/sbcl-${SBCL_VERSION}
RUN sh make.sh \
      --without-immobile-space \
      --without-immobile-code \
      --without-compact-instance-header \
      --fancy \
      --dynamic-space-size=4Gb \
      --prefix=/usr/local

RUN sh install.sh

# =============================================================================
# Stage 2: Build ACL2
# =============================================================================
FROM ubuntu:24.04 AS acl2-builder

# Copy SBCL from builder
COPY --from=sbcl-builder /usr/local /usr/local

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    libssl-dev \
    make \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root

# ACL2 version arguments
# ACL2_COMMIT: The commit hash or ref to build (workflow passes full hash)
# ACL2_BUILD_TYPE: "master" or "commit" - controls git branch setup
#   - master: sets up local master branch with upstream tracking (git pull works)
#   - commit: leaves as detached HEAD (for non-master refs)
ARG ACL2_COMMIT=master
ARG ACL2_BUILD_TYPE=master

# Clone ACL2 with shallow history
# Git is included so users can update ACL2 inside the container.
RUN git init acl2 && \
    cd acl2 && \
    git remote add origin https://github.com/acl2/acl2.git && \
    git fetch --depth 1 origin ${ACL2_COMMIT} && \
    if [ "${ACL2_BUILD_TYPE}" = "master" ]; then \
      git update-ref refs/remotes/origin/master FETCH_HEAD && \
      git checkout -b master FETCH_HEAD && \
      git branch --set-upstream-to=origin/master master; \
    else \
      git checkout FETCH_HEAD; \
    fi

# --------------------------------------------------------------------------
# ALTERNATIVE: Zipball download (smaller image, no git required)
#
# Pros: ~75-125 MB smaller image, faster download
# Cons: No "git pull" capability, requires ACL2_SNAPSHOT_INFO for version banner
#
# To use zipball instead:
#   1. Remove `git` from apt-get install above, add `unzip`
#   2. Replace the git clone above with:
#        ARG ACL2_SNAPSHOT_INFO="Local Docker build from ACL2 ${ACL2_COMMIT}"
#        RUN curl -fsSL "https://api.github.com/repos/acl2/acl2/zipball/${ACL2_COMMIT}" -o acl2.zip \
#            && unzip -q acl2.zip \
#            && mv acl2-acl2-* acl2 \
#            && rm acl2.zip
#        ENV ACL2_SNAPSHOT_INFO=${ACL2_SNAPSHOT_INFO}
#   3. Remove `git` from runtime stage apt-get install
# --------------------------------------------------------------------------

WORKDIR /root/acl2

# Create SBCL wrapper script for building ACL2
# Use 4GB for build phase (GitHub runners have ~7GB RAM)
# Users can set higher values at runtime for full regressions (32GB recommended)
RUN echo '#!/bin/sh' > /usr/local/bin/sbcl-acl2 && \
    echo 'exec /usr/local/bin/sbcl --dynamic-space-size 4000 "$@"' >> /usr/local/bin/sbcl-acl2 && \
    chmod +x /usr/local/bin/sbcl-acl2

# Test that SBCL works before building
RUN /usr/local/bin/sbcl-acl2 --version

# Build ACL2 (show make.log on failure for debugging)
RUN make LISP=/usr/local/bin/sbcl-acl2 || (cat make.log && exit 1)

# Generate certdep files and detect ACL2 features.
# This is a lightweight alternative to "make basic" (which certifies books).
# Without this step, cert.pl fails with "Missing build/acl2-version.certdep".
# See books/build/features.sh for details on what this generates.
RUN cd books && make ACL2=/root/acl2/saved_acl2 build/Makefile-features

# Note: Books are NOT certified in this stage.
# The 'runtime' image ships them uncertified; the 'kcerts' and 'allcerts'
# stages below certify them (kestrel/top's dependency tree and the full
# regression suite, respectively).

# =============================================================================
# Stage 3: Common runtime environment (shared by all final targets)
# =============================================================================
FROM ubuntu:24.04 AS runtime-base

# OCI labels (additional labels added by workflow)
LABEL org.opencontainers.image.title="ACL2"
LABEL org.opencontainers.image.description="ACL2 theorem prover built on SBCL"
LABEL org.opencontainers.image.licenses="BSD-3-Clause"
LABEL org.opencontainers.image.url="https://www.cs.utexas.edu/~moore/acl2/"

# Runtime dependencies
# - build-essential: some books (e.g., quicklisp) compile C code during certification
# - git: allows "git pull" to update ACL2 inside the container
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    git \
    libssl3 \
    make \
    perl \
    && rm -rf /var/lib/apt/lists/*

# Create read-only test file required by books/oslib/tests/copy certification
RUN touch /root/foo && chmod a-w /root/foo

# ACL2 environment setup
# - bin/ contains the 'acl2' launcher script
# - books/build/ contains cert.pl and other build tools
ENV ACL2_ROOT="/root/acl2"
ENV ACL2="${ACL2_ROOT}/saved_acl2"
ENV PATH="${ACL2_ROOT}/bin:${ACL2_ROOT}/books/build:${PATH}"

# USER is required by oslib::default-tempfile-aux
ENV USER="root"

WORKDIR /root/acl2

CMD ["acl2"]

# =============================================================================
# Stage 4: Lean runtime image (build target: runtime)
# =============================================================================
FROM runtime-base AS runtime

# Copy SBCL runtime
COPY --from=sbcl-builder /usr/local /usr/local

# Copy ACL2
COPY --from=acl2-builder /root/acl2 /root/acl2

# Optional: Remove .out files after book certification to save space.
# Uncomment if disk space becomes an issue during large regressions.
# ENV CERT_PL_RM_OUTFILES="1"

# =============================================================================
# Stage 5: Build the STP solver from source (used via 'cert-base')
# =============================================================================
# STP is not packaged for Ubuntu, so we build it (and its minisat dependency)
# from source.  STP is used by the Axe toolkit (books/kestrel/axe); the books
# build system enables the STP-dependent books when 'stp --version' works
# (see books/build/features.sh).
FROM ubuntu:24.04 AS stp-builder

# STP release tag, and the commit of STP's minisat fork to build against.
# (The minisat fork has no releases, so we pin a known-good commit.)
ARG STP_VERSION=2.4.1
ARG MINISAT_COMMIT=14c78206cd12d1d36b7e042fa758747c135670a4

RUN apt-get update && apt-get install -y --no-install-recommends \
    bison \
    build-essential \
    ca-certificates \
    cmake \
    flex \
    git \
    libboost-program-options-dev \
    libgmp-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Build minisat (STP's fork).  Install both into this stage (so the STP build
# can find it) and into /stage (staging tree copied into the final image).
RUN git init minisat && \
    cd minisat && \
    git remote add origin https://github.com/stp/minisat && \
    git fetch --depth 1 origin ${MINISAT_COMMIT} && \
    git checkout FETCH_HEAD && \
    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build -j"$(nproc)" && \
    cmake --install build && \
    DESTDIR=/stage cmake --install build

# Build STP.
# - lib/extlib-abc is a required submodule.
# - STP_ALLOCATOR=system avoids needing the mimalloc submodule.
# - The Python interface is not needed (Axe invokes the stp executable).
RUN git clone --depth 1 --branch ${STP_VERSION} https://github.com/stp/stp && \
    cd stp && \
    git submodule update --init --depth 1 lib/extlib-abc && \
    cmake -S . -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DENABLE_PYTHON_INTERFACE=OFF \
      -DSTP_ALLOCATOR=system && \
    cmake --build build -j"$(nproc)" && \
    cmake --install build && \
    DESTDIR=/stage cmake --install build && \
    ldconfig && \
    stp --version

# =============================================================================
# Stage 6: Common certification environment (shared by 'kcerts' and 'allcerts')
# =============================================================================
# Starts from the lean runtime image and adds:
#   - STP (for Axe) and Z3 (for Smtlink)
#   - a shared certify-books-and-clean script (used by both cert stages)
# No books are certified in this stage.
FROM runtime AS cert-base

# Use bash with pipefail so failures aren't masked by pipes (e.g. tee below).
# (SHELL is inherited by the 'kcerts' and 'allcerts' stages.)
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG Z3_SOLVER_VERSION=5.0.0.0

# - python3/python3-venv: for the Smtlink solver setup below
# - libboost-program-options1.83.0: runtime library needed by the stp
#   executable (its other library dependencies are either copied from
#   stp-builder below or already present via build-essential)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libboost-program-options1.83.0 \
    python3 \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# ---- STP (for Axe) ----
COPY --from=stp-builder /stage/usr/local/ /usr/local/
RUN ldconfig && stp --version

# ---- Z3 (for Smtlink) ----
# The z3-solver PyPI package provides the z3 executable AND the matching
# Python bindings in one place: /root/.venvs/smtlink/bin contains 'z3' and
# 'python'.  We append that directory to PATH so that:
#   - books/build/features.sh finds 'z3 --version' and enables the
#     Smtlink-dependent books (OS_HAS_SMTLINK), and
#   - it does not shadow the system python3.
RUN python3 -m venv /root/.venvs/smtlink && \
    /root/.venvs/smtlink/bin/pip install --no-cache-dir "z3-solver==${Z3_SOLVER_VERSION}"
ENV PATH="${PATH}:/root/.venvs/smtlink/bin"

# Smtlink reads its configuration from $SMT_HOME/smtlink-config, then
# $HOME/smtlink-config, then the smtlink book directory (see
# books/projects/smtlink/config.lisp).  We write $HOME/smtlink-config with an
# absolute path BEFORE certification, so this value is baked into the
# certified smtlink books and does not depend on PATH at proof time.
RUN printf 'smt-cmd=/root/.venvs/smtlink/bin/python\n' > /root/smtlink-config

# Delete each book's .cert.out file as soon as it certifies successfully.
# This keeps disk usage down during the regression, and the .cert.out files
# of FAILED certifications are kept (useful for debugging).  We leave this
# set in the final image; users certifying additional books get the same
# behavior, which keeps committed containers small.
ENV CERT_PL_RM_OUTFILES="1"

# Sanity-check both solvers exactly the way the books use them, BEFORE
# spending hours on the regression:
# - z3/python check mirrors books/projects/smtlink/README.md
# - teststp.bash is Axe's own end-to-end STP test; it must print "Valid."
RUN z3 --version && \
    /root/.venvs/smtlink/bin/python -c "import z3; print('z3 python bindings:', z3.get_version_string())" && \
    out="$(bash books/kestrel/axe/teststp.bash)" && \
    echo "$out" && \
    echo "$out" | grep -q 'Valid\.' && \
    rm -f books/kestrel/axe/teststp.out

# Shared certification driver, used by the 'kcerts' and 'allcerts' stages.
# It runs the given certification command from the books/ directory and, on
# success, removes the certification artifacts not needed by include-book.
# Notes:
# - Each cert stage runs this in a SINGLE RUN instruction: the cleanup must
#   happen in the same layer as the certification, because deleting files in
#   a later layer would not reduce image size.
# - What include-book needs: the .lisp sources, the .cert files, and the
#   compiled .fasl files.  .port files are only read when including
#   UNCERTIFIED books (see the ACL2 sources, other-events.lisp), so we delete
#   a .port only when the book's .cert exists.
# - .cert.out files of successful books were already removed during the run
#   by CERT_PL_RM_OUTFILES; failed books keep theirs, which is how the
#   failure report below identifies them.
COPY <<'EOF' /usr/local/bin/certify-books-and-clean
#!/bin/bash
# Usage: certify-books-and-clean <certification command...>
# Runs the command from ${ACL2_ROOT}/books, then cleans up (see Dockerfile).
# Strict: exits nonzero if the command fails, listing the failed books.
set -u -o pipefail
cd "${ACL2_ROOT}/books"
if "$@" 2>&1 | tee /tmp/certify.log ; then
  echo "Certification succeeded."
  echo "Removing certification artifacts not needed by include-book..."
  find . -type f \( -name '*.cert.out' -o -name '*.acl2x.out' \
       -o -name '*.pcert0.out' -o -name '*.pcert1.out' \
       -o -name '*.cert.time' -o -name '*.acl2x' \
       -o -name '*.pcert0' -o -name '*.pcert1' \
       -o -name '*@expansion.lsp' -o -name 'workxxx*' \) -delete
  find . -type f -name '*.port' \
       -exec bash -c 'for p; do [[ -f "${p%.port}.cert" ]] && rm -f -- "$p"; done' _ {} +
  rm -f /tmp/certify.log
  echo "Final books directory size:"
  du -sh .
else
  echo "=============================================================="
  echo "CERTIFICATION FAILED.  Books whose certification failed"
  echo "(each kept its .cert.out file; see the log above for details,"
  echo "or search it for 'CERTIFICATION FAILED'):"
  find . -name '*.cert.out' | sort
  echo "=============================================================="
  exit 1
fi
EOF
RUN chmod +x /usr/local/bin/certify-books-and-clean

# =============================================================================
# Stage 7: Kcerts image (build target: kcerts)
# =============================================================================
# Certifies kestrel/top and every book it depends on, using cert.pl.
# --keep-going: one broken book doesn't hide the others; cert.pl still exits
# nonzero at the end if anything failed, which fails this build (strict mode:
# no image is produced).
FROM cert-base AS kcerts

LABEL org.opencontainers.image.title="ACL2 (kestrel books certified)"
LABEL org.opencontainers.image.description="ACL2 theorem prover built on SBCL, with the books reachable from kestrel/top certified and the STP and Z3 solvers included"

ARG CERT_JOBS=

RUN J="${CERT_JOBS:-$(nproc)}" && \
    echo "Certifying kestrel/top and its dependencies with -j${J}..." && \
    certify-books-and-clean cert.pl -j "${J}" --keep-going kestrel/top

# =============================================================================
# Stage 8: Allcerts image (build target: allcerts)
# =============================================================================
# Certifies all books in the standard "make regression" suite: all books
# except a small SLOW_BOOKS list (see books/GNUmakefile).  The regression
# runs with -k (keep going), so every book that can certify does; make exits
# nonzero at the end if anything failed, which fails this build (strict mode:
# no image is produced).
#
# This stage builds on 'kcerts', so the kestrel books are already certified
# (make's up-to-dateness checks skip them; their .cert files are intact even
# though kcerts' cleanup removed .port/.cert.time files) and the regression
# certifies only the remaining books.  Building this target therefore builds
# the kcerts stage first; on a runner that has already built kcerts for the
# same ACL2 commit and build args, those layers come from the Docker cache.
FROM kcerts AS allcerts

LABEL org.opencontainers.image.title="ACL2 (all regression books certified)"
LABEL org.opencontainers.image.description="ACL2 theorem prover built on SBCL, with all regression books certified and the STP and Z3 solvers included"

ARG CERT_JOBS=

RUN J="${CERT_JOBS:-$(nproc)}" && \
    echo "Certifying the full regression suite with -j${J}..." && \
    certify-books-and-clean make -j"${J}" regression ACL2="${ACL2}"
