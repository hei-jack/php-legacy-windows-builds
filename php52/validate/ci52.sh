#!/bin/bash
# Build PHP 5.2 from a release tarball (+ optional patches) and run tests.
# usage: ci52.sh <label> [--zts] [--debug]
# Mounts: /src/php-5.2.17.tar.gz, /patches/*.patch (optional, applied in name order),
#         /tests (targeted .phpt, optional), /out (results).
# QUICK=1: targeted tests only. SUITES: test dirs (default Zend tests ext/session ext/standard/tests).
set -uo pipefail
label=$1; shift
out=/out/$label
log() { echo "[$(date +%T)] $*" | tee -a $out.summary; }
: > $out.summary

mkdir -p /build && cd /build && tar -xzf /src/php-5.2.17.tar.gz && cd php-5.2.17 || { log "EXTRACT FAILED"; exit 1; }
for p in $(ls /patches/*.patch 2>/dev/null | sort); do
  # git apply, like fetch.ps1: some test files contain NUL bytes and come as git binary patches
  GIT_CEILING_DIRECTORIES=/build git apply --whitespace=nowarn "$p" || { log "PATCH FAILED: $(basename $p)"; exit 1; }
  log "applied $(basename $p)"
done

# The modules the official Windows php5ts.dll has built in (minus odbc/com_dotnet). CLI+CGI are built by default.
cfg="--disable-all --without-pear --enable-session --with-pcre-regex --enable-spl --enable-bcmath --enable-calendar --enable-ctype --enable-ftp --enable-hash --enable-filter --enable-json --with-iconv --enable-libxml --enable-dom --enable-simplexml --enable-xml --enable-xmlreader --enable-xmlwriter --enable-wddx --enable-tokenizer --with-zlib"
for opt in "$@"; do
  case $opt in
    --zts)   cfg="$cfg --enable-maintainer-zts" ;;
    --debug) cfg="$cfg --enable-debug" ;;
  esac
done
log "configure $cfg"
./configure $cfg > $out.configure.log 2>&1 || { log "CONFIGURE FAILED"; tail -5 $out.configure.log >> $out.summary; exit 1; }
make -j8 > $out.make.log 2>&1 || { log "MAKE FAILED"; tail -40 $out.make.log >> $out.summary; exit 1; }
log "build ok: $(sapi/cli/php -v | head -1)"
grep -E 'warning:' $out.make.log | grep -E "/(Zend|main|ext|regex|sapi)/" | sort -u > $out.warnings
grep -qE 'makes (pointer from integer|integer from pointer)' $out.warnings && log "WARNING: pointer/integer mix-ups (see $label.warnings)"
grep -q "implicit declaration" $out.warnings && log "WARNING: implicit declarations (see $label.warnings)"
mkdir -p /out/bin/$label && cp sapi/cli/php sapi/cgi/php-cgi run-tests.php /out/bin/$label/

export TEST_PHP_EXECUTABLE=$PWD/sapi/cli/php TEST_PHP_CGI_EXECUTABLE=$PWD/sapi/cgi/php-cgi NO_INTERACTION=1 REPORT_EXIT_STATUS=0
if [ -d /tests ]; then
  mkdir -p /tmp/t && cp /tests/*.phpt /tmp/t/
  sapi/cli/php run-tests.php /tmp/t > $out.targeted.log 2>&1
  for t in /tmp/t/*.phpt; do
    name=$(sed -n '2p' "$t")
    if sed -n '/^\(FAILED\|BORKED\) TEST SUMMARY/,/^=====/p' $out.targeted.log | grep -qF "[$t]"; then echo "FAIL $name"
    elif tr '\r' '\n' < $out.targeted.log | grep -qE "^SKIP .*\[$t\]"; then echo "SKIP $name"
    else echo "PASS $name"; fi
  done | sort > $out.targeted
  log "targeted: $(grep -c '^PASS' $out.targeted) passed, $(grep -c '^FAIL' $out.targeted) failed, $(grep -c '^SKIP' $out.targeted) skipped"
fi
if [ "${QUICK:-0}" != 1 ]; then
  sapi/cli/php run-tests.php ${SUITES:-Zend tests ext/session ext/standard/tests ext/spl ext/date ext/pcre ext/reflection ext/bcmath ext/calendar ext/ctype ext/ftp ext/hash ext/filter ext/json ext/iconv ext/libxml ext/dom ext/simplexml ext/xml ext/xmlreader ext/xmlwriter ext/wddx ext/tokenizer ext/zlib} > $out.tests.log 2>&1
  sed -n '/^FAILED TEST SUMMARY/,/^=====/p' $out.tests.log | grep -oE '\[[^]]+\.phpt\]' | tr -d '[]' | sed 's|^/build/php-5.2.17/||' | sort -u > $out.fails
  log "$(grep -E '^Tests (passed|failed)' $out.tests.log | tr -s ' ' | tr '\n' ' ')"
fi
log done
