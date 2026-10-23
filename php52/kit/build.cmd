@echo off
rem Builds the patched PHP 5.2.17 core (php5ts.dll/php5.dll, php.exe, php-cgi.exe, php-win.exe,
rem php5isapi.dll) with Visual C++ 6.0, then lays it over the official 5.2.17 zips, so the official
rem ext\*.dll and third-party DLLs are reused unchanged.
rem
rem Prerequisites on the VM: Visual C++ 6.0 SP6, Platform SDK February 2003 (5.2.3790.0, the last
rem one for VC6; it also provides mc.exe). The Server 2003 SP1 SDK (5.2.3790.1830) may work: its
rem libraries need bufferoverflowu.lib, which is then added automatically.
rem Run kit\fetch.ps1 on a modern machine first and copy its output folder here (path without
rem spaces, e.g. C:\php52kit).
rem
rem usage:  C:\php52kit\kit\build.cmd [ts^|nts^|all]          (default: all)
rem   VC6DIR  defaults to C:\Program Files\Microsoft Visual Studio\VC98
rem   PSDKDIR folder with SetEnv.Bat/SetEnv.Cmd; defaults to C:\Program Files\Microsoft SDK
rem           (February 2003), else C:\Program Files\Microsoft Platform SDK (Server 2003 SP1).
rem           If the SDK environment is already set in this window, that is used as is.
rem   APACHE22  dir with include\ and lib\ of Apache 2.2, to also build php5apache2_2.dll (TS);
rem             defaults to the kit's apache22 folder (from fetch.ps1). Set APACHE22=none to skip.

setlocal EnableExtensions EnableDelayedExpansion
for %%I in ("%~dp0..") do set "KIT=%%~fI"
set "WHAT=%~1"
if "%WHAT%"=="" set WHAT=all
set "LOG=%KIT%\build.log"
if not defined APACHE22 if exist "%KIT%\apache22\include\httpd.h" set "APACHE22=%KIT%\apache22"
if /i "%APACHE22%"=="none" set APACHE22=
echo. > "%LOG%"

rem ---------------------------------------------------------------- toolchain
if not defined VC6DIR set "VC6DIR=C:\Program Files\Microsoft Visual Studio\VC98"
rem Platform SDK environment script: SetEnv.Bat (February 2003) or SetEnv.Cmd (Server 2003 SP1)
set "PSDKENV="
if defined PSDKDIR call :find_sdk "%PSDKDIR%"
if not defined PSDKENV call :find_sdk "C:\Program Files\Microsoft SDK"
if not defined PSDKENV call :find_sdk "C:\Program Files\Microsoft Platform SDK"
cl >nul 2>&1
if errorlevel 9009 if exist "%VC6DIR%\Bin\VCVARS32.BAT" call "%VC6DIR%\Bin\VCVARS32.BAT"
cl >nul 2>&1
if errorlevel 9009 (echo ERROR: cl.exe not found - run from a VC6 command prompt or set VC6DIR & exit /b 1)
if defined PSDKENV (
  call "%PSDKENV%" /XP32 /RETAIL
) else (
  echo NOTE: no Platform SDK SetEnv script found ^(set PSDKDIR^); using the current INCLUDE and LIB
)
rem SDKs after February 2003 ship libraries built with /GS (buffer security checks); VC6 links them
rem only with bufferoverflowu.lib. link.exe reads extra arguments from the LINK variable.
if exist "%PSDKDIR%\Lib\bufferoverflowu.lib" (
  set "LINK=bufferoverflowu.lib %LINK%"
  echo NOTE: this Platform SDK is newer than February 2003 ^(not supported with VC6 by Microsoft^); linking bufferoverflowu.lib
)
cl 2>&1 | find "Version 12.00" >nul
if errorlevel 1 (echo ERROR: cl.exe is not Visual C++ 6.0 ^(12.00^) & exit /b 1)
mc -? >nul 2>&1
if errorlevel 9009 (echo ERROR: mc.exe ^(message compiler^) not found - it comes with the Platform SDK & exit /b 1)
rem Whether SetEnv ran here or before, the SDK headers must be in INCLUDE: VC6's own (1998) are
rem too old for PHP 5.2. These two exist only in the Platform SDK.
set "SDKHDR="
for %%H in (wspiapi.h strsafe.h) do if not defined SDKHDR set "SDKHDR=%%~$INCLUDE:H"
if not defined SDKHDR (echo ERROR: Platform SDK headers are not in INCLUDE - install the Core SDK with its Build Environment, or set PSDKDIR to the folder with SetEnv.Bat/SetEnv.Cmd & exit /b 1)
call :log "toolchain ok (SDK header: !SDKHDR!)"

rem configure.js insists on bison and flex although the tarball ships the generated files.
rem These stubs fail loudly if the build ever tries to regenerate them.
set "TOOLS=%KIT%\tools"
if not exist "%TOOLS%\bison.exe" (
  mkdir "%TOOLS%" 2>nul
  > "%TOOLS%\stub.c" echo #include ^<stdio.h^>
  >>"%TOOLS%\stub.c" echo int main^(int argc, char **argv^) { fprintf^(stderr, "%%s is a stub: a generated parser/scanner looks out of date, use the release tarball's files\n", argv[0]^); return 1; }
  pushd "%TOOLS%" && cl /nologo stub.c /Febison.exe >>"%LOG%" 2>&1 && copy /y bison.exe flex.exe >nul & popd
)
set "PATH=%TOOLS%;%PATH%"

rem ---------------------------------------------------------------- dependencies (static, /MD)
set "PB=%KIT%\php_build"
if exist "%PB%\lib\libxml2_a_dll.lib" goto deps_done
mkdir "%PB%\include\libxml" "%PB%\lib" 2>nul

call :log "zlib"
pushd "%KIT%\deps\zlib-1.3.1"
nmake /nologo -f win32\Makefile.msc zlib.lib >>"%LOG%" 2>&1 || (popd & goto fail)
copy /y zlib.lib "%PB%\lib\" >nul & copy /y zlib.h "%PB%\include\" >nul & copy /y zconf.h "%PB%\include\" >nul
popd

call :log "libiconv"
pushd "%KIT%\deps\libiconv-1.11.1"
copy /y config.h.msvc config.h >nul
copy /y libcharset\include\localcharset.h lib\localcharset.h >nul 2>&1
pushd libcharset & nmake /nologo -f Makefile.msvc NO_NLS=1 MFLAGS=-MD all >>"%LOG%" 2>&1 & popd
copy /y libcharset\include\localcharset.h lib\localcharset.h >nul
copy /y include\iconv.h.msvc-static include\iconv.h >nul
pushd lib & nmake /nologo -f Makefile.msvc NO_NLS=1 MFLAGS=-MD all >>"%LOG%" 2>&1 || (popd & popd & goto fail)
popd
copy /y lib\iconv.lib "%PB%\lib\iconv_a.lib" >nul & copy /y lib\iconv.lib "%PB%\lib\iconv.lib" >nul
copy /y include\iconv.h "%PB%\include\" >nul
popd

call :log "libxml2"
pushd "%KIT%\deps\libxml2-2.9.14\win32"
cscript //nologo configure.js compiler=msvc cruntime=/MD iconv=yes zlib=no lzma=no icu=no ftp=no http=no python=no static=yes debug=no "include=%PB%\include" "lib=%PB%\lib" "prefix=%PB%" >>"%LOG%" 2>&1 || (popd & goto fail)
nmake /nologo -f Makefile.msvc libxmladll >>"%LOG%" 2>&1 || (popd & goto fail)
copy /y bin.msvc\libxml2_a_dll.lib "%PB%\lib\" >nul
copy /y ..\include\libxml\*.h "%PB%\include\libxml\" >nul
popd
:deps_done
rem PHP 5.2's configure requires arpa\nameser.h, php_network.h includes arpa/inet.h on Windows, and
rem basic_functions.c / dns.c include netdb.h: they came from php.net's old win32build/bindlib
rem packages. On Windows PHP uses no BIND code (the official php5ts.dll contains none; inet_aton is
rem PHP's own, in flock_compat.c) and zend_config.w32.h includes winsock2.h first, so stubs do.
if not exist "%PB%\include\arpa" mkdir "%PB%\include\arpa"
> "%PB%\include\arpa\nameser.h" echo /* stub: PHP 5.2's configure checks for this file; the Windows build uses no BIND code */
rem php_network.h #undefs FD_SETSIZE just before including arpa/inet.h: restore the value configure
rem passes (/D FD_SETSIZE=256, --enable-fd-setsize), which winsock2.h already sized fd_set with.
> "%PB%\include\arpa\inet.h" echo #include ^<winsock2.h^>
>> "%PB%\include\arpa\inet.h" echo #ifndef FD_SETSIZE
>> "%PB%\include\arpa\inet.h" echo #define FD_SETSIZE 256
>> "%PB%\include\arpa\inet.h" echo #endif
> "%PB%\include\netdb.h" echo #include ^<winsock2.h^>
rem win32\glob.h (BSD code) includes sys/cdefs.h, only for __BEGIN_DECLS / __END_DECLS
if not exist "%PB%\include\sys" mkdir "%PB%\include\sys"
> "%PB%\include\sys\cdefs.h" echo #ifndef __BEGIN_DECLS
>> "%PB%\include\sys\cdefs.h" echo #define __BEGIN_DECLS
>> "%PB%\include\sys\cdefs.h" echo #define __END_DECLS
>> "%PB%\include\sys\cdefs.h" echo #endif
call :log "dependencies ready in %PB%"

rem ---------------------------------------------------------------- PHP
if /i "%WHAT%"=="all" (call :php ts || goto fail
                       call :php nts || goto fail) else (call :php %WHAT% || goto fail)
call :log "done - see %KIT%\dist and run kit\check.cmd"
exit /b 0

:php
set "FL=%~1"
set "SRC=%KIT%\build-%FL%\php-5.2.17"
call :log "PHP %FL%: copying source"
if exist "%KIT%\build-%FL%" rmdir /s /q "%KIT%\build-%FL%"
xcopy /e /i /q /k "%KIT%\src\php-5.2.17" "%SRC%" >nul || exit /b 1
pushd "%SRC%"
rem buildconf.bat's exit code is not usable: on XP its last line (SET of an undefined variable to
rem nothing) leaves errorlevel 1 even when it worked. Check its result instead.
if exist configure.js del configure.js
call buildconf.bat >>"%LOG%" 2>&1
if not exist configure.js (popd & echo buildconf did not create configure.js & exit /b 1)
set "CFG=--with-php-build=%PB% --enable-cli-win32"
if /i "%FL%"=="ts" (set "CFG=!CFG! --enable-isapi") else (set "CFG=!CFG! --disable-zts")
rem The Apache 2.2 module: PHP 5.2's configure only looks in php_build\include\apache2_2 and
rem php_build\lib\apache2_2 for Apache's headers and import libraries.
if /i "%FL%"=="ts" if defined APACHE22 (
  if not exist "%PB%\include\apache2_2" mkdir "%PB%\include\apache2_2"
  if not exist "%PB%\lib\apache2_2" mkdir "%PB%\lib\apache2_2"
  xcopy /e /i /q /y "%APACHE22%\include" "%PB%\include\apache2_2" >nul
  for %%L in (libhttpd.lib libapr-1.lib libaprutil-1.lib) do copy /y "%APACHE22%\lib\%%L" "%PB%\lib\apache2_2\" >nul
  set "CFG=!CFG! --enable-apache2-2handler"
)
call :log "PHP %FL%: configure !CFG!"
cscript //nologo configure.js !CFG! > "%KIT%\configure-%FL%.log" 2>&1 || (popd & exit /b 1)
call :log "PHP %FL%: nmake"
nmake /nologo >> "%KIT%\nmake-%FL%.log" 2>&1 || (popd & echo see %KIT%\nmake-%FL%.log & exit /b 1)
popd
if /i "%FL%"=="ts" if defined APACHE22 if not exist "%SRC%\Release_TS\php5apache2_2.dll" (
  echo php5apache2_2.dll was not built - see "Could not find apache2.2" in %KIT%\configure-ts.log
  exit /b 1
)

rem dist = official zip + our core binaries
if /i "%FL%"=="ts" (set "REL=Release_TS" & set "DLL=php5ts.dll" & set "OFF=%KIT%\official\ts") else (set "REL=Release" & set "DLL=php5.dll" & set "OFF=%KIT%\official\nts")
set "DIST=%KIT%\dist\php-5.2.17-cve2026-%FL%-Win32-VC6-x86"
if exist "%DIST%" rmdir /s /q "%DIST%"
xcopy /e /i /q /k "%OFF%" "%DIST%" >nul || exit /b 1
for %%F in (%DLL% php.exe php-cgi.exe php-win.exe php5isapi.dll php5apache2_2.dll) do (
  if exist "%SRC%\%REL%\%%F" copy /y "%SRC%\%REL%\%%F" "%DIST%\" >nul
)
copy /y "%SRC%\php.ini-dist" "%DIST%\" >nul & copy /y "%SRC%\php.ini-recommended" "%DIST%\" >nul
if not exist "%DIST%\dev" mkdir "%DIST%\dev"
for %%F in (php5ts.lib php5.lib) do if exist "%SRC%\%REL%\%%F" copy /y "%SRC%\%REL%\%%F" "%DIST%\dev\" >nul
call :log "PHP %FL%: %DIST%"
exit /b 0

:find_sdk
if exist "%~1\SetEnv.Bat" (set "PSDKDIR=%~1" & set "PSDKENV=%~1\SetEnv.Bat" & exit /b 0)
if exist "%~1\SetEnv.Cmd" (set "PSDKDIR=%~1" & set "PSDKENV=%~1\SetEnv.Cmd")
exit /b 0

:log
echo [%TIME:~0,8%] %~1
echo [%TIME:~0,8%] %~1 >> "%LOG%"
exit /b 0

:fail
echo BUILD FAILED - see %LOG% ^(and configure-*.log / nmake-*.log^)
exit /b 1
