# PHP 5.2.17 with security backports (Windows, Visual C++ 6.0)

For servers that must stay on PHP 5.2 (e.g. 5.2.14 on Windows Server 2008 R2). This rebuilds
**only the PHP core** — `php5ts.dll` / `php5.dll`, `php.exe`, `php-cgi.exe`, `php-win.exe`,
`php5isapi.dll` — from the 5.2.17 release tarball plus the patches below, with the same
compiler as the official builds (VC6, msvcrt.dll). The official 5.2.17 `ext\php_*.dll` and the
third-party DLLs are reused unchanged, so the build is a drop-in replacement for an official
5.2.17 install.

> PHP 5.2 has had no upstream fixes since January 2011. This narrows the gap for the parts of PHP
> every request goes through; it does not make 5.2 safe. See [Not covered](#not-covered).

## What's patched

Built-in code only (the core, the request parser, and the modules compiled into php5ts.dll:
standard, session, SPL, pcre, date, xml/dom/libxml, ftp, calendar, ...).

| # | CVE | What | Source |
|---|-----|------|--------|
| 1 | CVE-2026-109618, CVE-2026-109619 | OOM/overflow errors exit instead of bailing out; stale request state reset at shutdown; multipart part headers limited to Content-Disposition/Content-Type | port of php-src 712e60f |
| 2 | CVE-2011-4885 | `max_input_vars` (default 1000) against the hash-collision DoS — final 5.3 design, so not affected by CVE-2012-0830 | php-src 5.3.11+ |
| 3 | CVE-2023-0662 | `max_multipart_body_parts` (default `max_input_vars` + `max_file_uploads`) | upstream, as shipped by Freexian for 5.6 |
| 4 | CVE-2011-2202, CVE-2012-1172 | upload filename path injection; `$_FILES` corruption by unbalanced brackets | Debian lenny, Ubuntu hardy |
| 5 | CVE-2011-1398, CVE-2012-4388 | `header()` response splitting via bare CR / NUL | Ubuntu hardy |
| 6 | CVE-2012-0831 | `magic_quotes_gpc` could stay off for the request | Ubuntu hardy (ZTS fix: no `TSRMLS_CC` in 5.2) |
| 7 | CVE-2015-4024 | quadratic CPU on multipart header continuation lines | upstream, hand-ported |
| 8 | CVE-2011-1148 | use-after-free in `substr_replace()` | Debian squeeze-lts |
| 9 | CVE-2011-1466 | integer overflow in `SdnToJulian()` (calendar) | Debian squeeze-lts |
| 10 | CVE-2011-1469 | crash in the FTP wrapper through an HTTP proxy | Debian squeeze-lts |
| 11 | CVE-2013-4113 | heap corruption in `xml_parse_into_struct()` | Debian squeeze-lts |
| 12 | CVE-2014-4721 | type confusion in `phpinfo()` | Debian squeeze-lts |
| 13–14 | CVE-2015-4022, CVE-2015-4643 | integer overflow in `ftp_genlist()` (FTP server reply) | Debian squeeze-lts |
| 15 | CVE-2011-1464 | buffer overrun in `printf` with a huge `precision` | Debian squeeze-lts |
| 16 | CVE-2012-2688 | overflow in `scandir()` | Debian squeeze-lts |
| 17 | CVE-2015-2305 | integer overflow in `regcomp()` (ereg) | Debian squeeze-lts |
| 18 | CVE-2012-1823, CVE-2012-2311 | php-cgi switches from the query string (plain CGI setups) | Ubuntu hardy + final upstream check |
| 19 | CVE-2015-4602 | type confusion in `__PHP_Incomplete_Class` (unserialize) | Debian squeeze-lts |
| 20 | CVE-2014-3669 | integer overflow in `unserialize()` on 32-bit | CentOS 5 php53 |
| 21 | CVE-2015-2787 | use-after-free in `unserialize()` via `__wakeup` | Debian squeeze-lts + NULL guard |
| 22 | CVE-2014-3515, CVE-2015-6831, CVE-2015-6834 | `SplObjectStorage::unserialize()`: non-array members (one line of serialized data segfaults stock 5.2.17), values kept alive for back-references | CentOS 5 php53, Debian squeeze-lts |
| 23 | CVE-2015-6835 | use-after-free in the session deserializers (reproduced on stock 5.2.17) | Debian squeeze-lts (prepared, never applied by Debian) |
| 24–26 | CVE-2006-7243, CVE-2015-2348, CVE-2015-3411/3412, CVE-2015-4025, CVE-2015-4598 | paths containing a NUL byte are rejected instead of silently truncated: include/require and about 60 functions and methods (file, dir, stat, link, hash, dom, xmlreader/writer, simplexml, zlib, SPL) | CentOS 5 php53, Debian squeeze-lts, written for 5.2's argument parsing |
| 27 | — | builds with libxml2 2.9 (opaque output buffers in DOM and SimpleXML) | php-src PHP-5.3 |
| 28 | — | php5ts.dll does not export libxml2's FTP/HTTP client, which the kit leaves out (no official extension imports it) | |
| 29 | — | version string `5.2.17-cve2026` | |

CVE-2015-6834's other part (bug #70172, nested `unserialize()`) does not apply: it needs the
shared unserialize state of PHP 5.6, and 5.2 gives every nested call its own (checked with the
upstream test; upstream's "no objects without var_hash" change was left out because php_pdo's
`FETCH_SERIALIZE` relies on it).

The vendor patches were taken from the last Debian squeeze-lts (php5 5.3.3.1-7+squeeze29),
Debian lenny (5.2.6.dfsg.1-1+lenny16), Ubuntu hardy (5.2.4-2ubuntu5.27) and CentOS 5.11
packages, checked against 5.2.17 and adjusted where needed. `var_unserializer.c` is regenerated
with re2c 0.13.5, the version 5.2.17 was released with, in the same style (`-b -i`), so the
patches only carry real changes.

The kit also builds php5ts.dll against **zlib 1.3.1** and **libxml2 2.9.14** instead of the
official zlib 1.2.3 / libxml2 2.7.7 (both have many CVEs). php5ts.dll re-exports both libraries
to the official extensions (php_xsl, php_soap, ...), which is fine because both kept their
binary interface; `check.cmd` verifies the exports.

## Behaviour changes to know about

- A request with more than 1000 GET/POST/COOKIE variables (or form fields) is cut at 1000 with a
  warning — raise `max_input_vars` if an application posts huge forms.
- Running out of `memory_limit` ends the process with the fatal error, without running shutdown
  functions or destructors (same as the 7.x/5.6 builds in this repo).
- Multipart parts keep only `Content-Disposition` and `Content-Type` headers; the first of each
  wins.
- An upload whose field name has unbalanced brackets (`file[`) is ignored.
- `header()` refuses a value with a bare CR or a NUL byte.
- A path with a NUL byte gives the warning "Path must not contain NUL bytes" and FALSE (an
  exception for the SPL constructors; `include` fails like a missing file, `require` is fatal).
  `file_exists()`, `is_file()`, `stat()` and the like just return FALSE.
- `session_decode()` returns FALSE (and the session is destroyed, with the existing warning) when
  the session data is corrupt, instead of loading part of it and returning TRUE.
- `SplObjectStorage::unserialize()` throws `UnexpectedValueException` when the members part is
  not an array.
- `version_compare(PHP_VERSION, '5.2.17')` is `-1` because of the `-cve2026` suffix (comparisons
  with any other version are unchanged).
- libxml2 2.9 rejects some pathological XML that 2.7 accepted (e.g. text nodes over 10 MB without
  `LIBXML_PARSEHUGE`, deep entity expansion). Two differences show up in PHP's own tests:
  `DOMDocument::saveHTML()`/`saveXML()` of a parsed HTML document puts `<html>`, `<head>`,
  `<title>` and `<body>` on separate lines (same content, different whitespace), and an
  `xi:include` pointing at another included subtree expands differently. The XML extensions'
  other tests behave as with libxml2 2.7/2.8.

## Not covered

- **Extensions shipped as DLLs** (php_mysql, php_gd2, php_curl, php_openssl, php_soap, php_mbstring,
  php_exif, ...): they are the official 2011 binaries with their own unfixed CVEs, and so are their
  libraries (OpenSSL 0.9.8, libmysql, ...). Only load the ones the application uses.
- NUL-byte path checks in the extension DLLs (gd, zip, bz2, openssl, ...) and in com_dotnet /
  odbc (built in, but Windows/ODBC-specific code that can't be validated outside the VM).
- XXE in libxml/SOAP (CVE-2013-1643): don't parse user-supplied XML with `LIBXML_NOENT` /
  `LIBXML_DTDLOAD`.
- Hash-collision DoS through `json_decode()` / `unserialize()` of attacker data (no distro fixed it).

## Build (route A: core only, VC6)

1. **On a modern machine** (PowerShell 5.1, Git for Windows):
   ```
   powershell -ExecutionPolicy Bypass -File php52\kit\fetch.ps1 -Out C:\php52kit
   ```
   Downloads the 5.2.17 tarball, the official TS/NTS zips and the dependency sources (all pinned by
   SHA-256), applies `php52\patches`, and leaves a self-contained `C:\php52kit`.
2. **Copy `C:\php52kit` to the VC6 VM** at the same path (no spaces). The VM needs Visual C++ 6.0
   SP6 and the Platform SDK February 2003, version 5.2.3790.0 (the last one that supports VC6;
   it also provides `mc.exe`). Windows XP SP3 or Server 2003, 32-bit, is the easiest host. The
   Server 2003 **SP1** SDK (5.2.3790.1830, installs to `…\Microsoft Platform SDK`) is not
   supported with VC6 by Microsoft but may work: `build.cmd` finds it and links
   `bufferoverflowu.lib`, which its `/GS`-compiled libraries need. If its headers trip VC6, the
   errors are at the top of `nmake-ts.log`.
3. On the VM: `C:\php52kit\kit\build.cmd` (or `build.cmd ts` / `build.cmd nts`). Set `VC6DIR` /
   `PSDKDIR` if they are not in the default folders; set `APACHE22` to also build
   `php5apache2_2.dll`. It builds zlib, libiconv and libxml2 as static libraries, then PHP, and
   writes `dist\php-5.2.17-cve2026-{ts,nts}-Win32-VC6-x86`: the official zip with the rebuilt core
   files laid over it.
4. `C:\php52kit\kit\check.cmd` (add `full` for the full test suites, slow): export/ABI check
   against what the official extensions import, every official extension loaded with both the
   rebuilt and the official PHP, and the targeted tests.

TS is for ISAPI and Apache (mod_php); NTS for IIS FastCGI (`php-cgi.exe`).

## Deploy

Stop the web server / app pool, back up the PHP folder, then copy from the dist folder into it:
`php5ts.dll` (or `php5.dll`), `php.exe`, `php-cgi.exe`, `php-win.exe`, `php5isapi.dll` (and
`php5apache2_2.dll` if built). Keep your `php.ini` and `ext\`; coming from 5.2.14, replacing
`ext\` with the official 5.2.17 one (included in the dist folder) is recommended, since the
extensions must match the core's 5.2.x API (same `API20060613`). Add to `php.ini` if needed:
```
max_input_vars = 1000
; max_multipart_body_parts = -1   (default: max_input_vars + max_file_uploads)
display_startup_errors = Off      ; with On, a startup warning stops POST parsing (5.2/5.3 behaviour)
```

## Validation (Linux, Docker)

`php52/validate/run-all.sh <work dir>` builds the tarball and the patched tree on Debian wheezy
with the modules the Windows php5ts.dll has built in, and runs the Zend, tests, standard,
session, SPL, date, pcre, reflection, bcmath, calendar, ctype, ftp, hash, filter, json, iconv,
libxml, dom, simplexml, xml, xmlreader, xmlwriter, wddx, tokenizer and zlib suites, plus
thread-safe and debug builds against the targeted tests in `php52/tests`, and a C89 check
(`-Wdeclaration-after-statement`: VC6 rejects declarations after statements).
Patches are applied with `git apply`, as `fetch.ps1` does: a few test files contain NUL bytes and
come as git binary patches. `regen-re2c.sh` regenerates `var_unserializer.c` after a change to
the `.re` file; `Zend/zend_vm_execute.h` is regenerated with `Zend/zend_vm_gen.php` (both
reproduce the tarball's files byte for byte before any change).

Results for this series (22 Oct 2026), about 6,085 tests:

| Build | Suites | Targeted (10) |
|---|---|---|
| 5.2.17 tarball | 25 failed | 4 passed, 6 failed (no fixes) |
| patched | the same 25 failures; the 10 tests the patches add pass | 10 passed |
| patched, thread-safe | — | 10 passed |
| patched, debug | — | 10 passed |
| patched, C89 check | 0 mixed declarations | — |

Some upstream tests are timing- or order-dependent and fail now and then on either build
(`ext/dom/tests/dom007.phpt`, which depends on libxml2's randomized hash order;
`ext/standard/tests/misc/time_sleep_until_basic.phpt`). The debug build's "implicit
declaration" warning is `php_dirname` in ext/xmlwriter, an upstream 5.2.17 issue in a file the
patches don't touch.

The same checks have **not** been run on a VC6 build yet: `check.cmd` does that on the build VM.
`fetch.ps1` was tested end to end (the kit's patched tree is byte-identical to the validated one),
and `check.cmd`'s extension and test steps were tried with the official binaries.
