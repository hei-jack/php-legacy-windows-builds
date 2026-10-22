#!/bin/bash
# Linux validation of the PHP 5.2.17 patch series (Docker, Debian wheezy):
#   base    = release tarball, full suites       (baseline)
#   patched = tarball + php52/patches, full suites
#   zts, debug = patched, thread-safe / debug builds, targeted tests only
# usage: php52/validate/run-all.sh <work dir>   (Windows path in Git Bash, e.g. C:/php-bp/v52)
# The work dir gets php-5.2.17.tar.gz (downloaded if missing) and out/ with the results.
set -eu
here=$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)
php52=$(dirname "$here")
W=${1:?work dir}
export MSYS_NO_PATHCONV=1
mkdir -p "$W/out" "$W/empty-patches"
[ -f "$W/php-5.2.17.tar.gz" ] || curl -sSfL -o "$W/php-5.2.17.tar.gz" https://museum.php.net/php5/php-5.2.17.tar.gz
echo "1abe07c1fdd64184708a3ba179abcfcca5662a4e0d2037eb2748b75abc42e767  $W/php-5.2.17.tar.gz" | sha256sum -c -
docker build -q -t php52-ci "$here"
run() { local label=$1 patches=$2 quick=$3; shift 3
  docker run --rm -e QUICK=$quick -v "$W":/src:ro -v "$patches":/patches:ro -v "$php52/tests":/tests:ro -v "$W/out":/out php52-ci ci52.sh $label "$@"; }
run base52    "$W/empty-patches" 0
run p52       "$php52/patches" 0
run p52-zts   "$php52/patches" 1 --zts
run p52-debug "$php52/patches" 1 --debug
cd "$W/out"
echo "== failing only with the patches:"; comm -13 base52.fails p52.fails
echo "== fixed by the patches:"; comm -23 base52.fails p52.fails
for l in base52 p52 p52-zts p52-debug; do echo "== $l"; grep -E 'targeted|Tests|WARNING' $l.summary || true; done
