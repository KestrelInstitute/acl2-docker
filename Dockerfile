# syntax=docker/dockerfile:1
#
# Multi-platform Dockerfile for ACL2 on SBCL
# Builds for linux/amd64 and linux/arm64
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
#   ACL2_COMMIT  - ACL2 commit/tag/branch to build (default: master)

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

# Note: Books are NOT certified during build.
# Users certify the books they need when running the image.

# =============================================================================
# Stage 3: Runtime image
# =============================================================================
FROM ubuntu:24.04

# OCI labels (additional labels added by workflow)
LABEL org.opencontainers.image.title="ACL2"
LABEL org.opencontainers.image.description="ACL2 theorem prover built on SBCL"
LABEL org.opencontainers.image.licenses="BSD-3-Clause"
LABEL org.opencontainers.image.url="https://www.cs.utexas.edu/~moore/acl2/"

# Copy SBCL runtime
COPY --from=sbcl-builder /usr/local /usr/local

# Copy ACL2
COPY --from=acl2-builder /root/acl2 /root/acl2

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

# Optional: Remove .out files after book certification to save space.
# Uncomment if disk space becomes an issue during large regressions.
# ENV CERT_PL_RM_OUTFILES="1"

WORKDIR /root/acl2

CMD ["acl2"]
