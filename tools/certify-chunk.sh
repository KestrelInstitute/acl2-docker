#!/bin/bash
# certify-chunk.sh — run one time-budgeted slice of the full book regression.
#
# This runs INSIDE an acl2 'cert-base' container (see the Dockerfile).  The
# calling workflow `docker commit`s the container afterward and pushes it as
# a checkpoint image, so certification progress persists across CI jobs that
# are individually limited to 6 hours (GitHub-hosted runners).  Certification
# with make/cert.pl is naturally resumable: a later chunk skips every book
# that is already certified.
#
# Usage: certify-chunk.sh BUDGET_SECONDS CERT_JOBS [TARGET]
#
# TARGET selects what to certify (default: regression):
#   regression  the full standard regression suite (make -k regression)
#   kestrel     kestrel/top and its dependency tree (cert.pl --keep-going),
#               i.e. the kcerts book set
#
# Writes /root/chunk-status with one of:
#   done      regression completed with no failures (artifacts cleaned up)
#   continue  time budget expired; re-run from the committed checkpoint
#   failed    regression completed but some books failed (.cert.out kept)
#   error     the make invocation died for some other reason
# and /root/chunk-cpu with the total per-book certification seconds this
# chunk performed (summed from cert.pl's "Built ... (N.NNs)" lines).
#
# The script always exits 0: the workflow reads /root/chunk-status to decide
# what to do, and a nonzero exit here would only obscure that.

set -u -o pipefail

budget="${1:?usage: certify-chunk.sh BUDGET_SECONDS CERT_JOBS [TARGET]}"
jobs="${2:?usage: certify-chunk.sh BUDGET_SECONDS CERT_JOBS [TARGET]}"
target="${3:-regression}"

case "${target}" in
  regression) cmd=(make -j"${jobs}" -k regression ACL2="${ACL2}") ;;
  kestrel)    cmd=(cert.pl -j "${jobs}" --keep-going kestrel/top) ;;
  *) echo "certify-chunk: unknown TARGET '${target}'" ; \
     echo error > /root/chunk-status ; echo 0 > /root/chunk-cpu ; exit 0 ;;
esac

cd "${ACL2_ROOT}/books"

echo "=== certify-chunk: target ${target}, budget ${budget}s, -j${jobs}, starting $(date -u +%FT%TZ)"

# SIGINT lets make and cert.pl shut their children down; anything still
# alive 120s later is killed hard.  timeout exits 124 iff the budget expired.
timeout --signal=INT --kill-after=120 "${budget}" \
  "${cmd[@]}" 2>&1 | tee /tmp/chunk.log
rc=${PIPESTATUS[0]}

# Total certification work done in this chunk (independent of parallelism).
cpu=$(grep -o 'Built .* ([0-9.]*s)' /tmp/chunk.log \
      | sed 's/.*(\([0-9.]*\)s)/\1/' \
      | awk '{t+=$1; n+=1} END {printf "%.0f %d", t, n}')
echo "${cpu%% *}" > /root/chunk-cpu
echo "=== certify-chunk: this chunk certified ${cpu##* } books," \
     "${cpu%% *} CPU-seconds of book work; make exit code ${rc}"

if [ "${rc}" -eq 0 ]; then
  echo "=== certify-chunk: regression COMPLETE, no failures."
  echo "Removing certification artifacts not needed by include-book..."
  # Keep in sync with certify-books-and-clean in the Dockerfile.
  find . -type f \( -name '*.cert.out' -o -name '*.acl2x.out' \
       -o -name '*.pcert0.out' -o -name '*.pcert1.out' \
       -o -name '*.cert.time' \
       -o -name '*.pcert0' -o -name '*.pcert1' \
       -o -name 'workxxx*' \) -delete
  rm -rf doc/manual/download
  echo "Final books directory size:"
  du -sh .
  echo done > /root/chunk-status
elif [ "${rc}" -eq 124 ]; then
  echo "=== certify-chunk: time budget expired; resume from the checkpoint."
  echo continue > /root/chunk-status
elif find . -name '*.cert.out' | grep -q . ; then
  echo "=============================================================="
  echo "=== certify-chunk: regression finished but some books FAILED"
  echo "(each kept its .cert.out file; search the log above for details):"
  find . -name '*.cert.out' | sort
  echo "=============================================================="
  echo failed > /root/chunk-status
else
  echo "=== certify-chunk: make died (exit ${rc}) without failed books;"
  echo "see the log above."
  echo error > /root/chunk-status
fi

rm -f /tmp/chunk.log
exit 0
