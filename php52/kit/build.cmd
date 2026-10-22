@echo off
rem Builds the patched PHP 5.2.17 core (php5ts.dll/php5.dll, php.exe, php-cgi.exe, php-win.exe,
rem php5isapi.dll) with Visual C++ 6.0, then lays it over the official 5.2.17 zips, so the official
rem ext\*.dll and third-party DLLs are reused unchanged.
rem
rem Prerequisites on the VM: Visual C++ 6.0 SP6, Platform SDK February 2003 (last one for VC6;
rem it also provides mc.exe). Run kit\fetch.ps1 on a modern machine first and copy its output
rem folder here (path without spaces, e.g. C:\php52kit).
rem
rem usage:  C:\php52kit\kit\build.cmd [ts^|nts^|all]          (default: all)
rem   VC6DIR  defaults to C:\Program Files\Microsoft Visual Studio\VC98
rem   PSDKDIR defaults to C:\Program Files\Microsoft SDK
rem   APACHE22=<dir with include\ and lib\ of Apache 2.2> also builds php5apache2_2.dll (TS)

setlocal EnableExtensions EnableDelayedExpansion
for %%I in ("%~dp0..") do set "KIT=%%~fI"
set "WHAT=%~1"
if "%WHAT%"=="" set WHAT=all
set "LOG=%KIT%\build.log"
echo. > "%LOG%"

rem ---------------------------------------------------------------- toolchain
if not defined VC6DIR set "VC6DIR=C:\Program Files\Microsoft Visual Studio\VC98"
if not defined PSDKDIR set "PSDKDIR=C:\Program Files\Microsoft SDK"
cl >nul 2>&1
if errorlevel 9009 if exist "%VC6DIR%\Bin\VCVARS32.BAT" call "%VC6DIR%\Bin\VCVARS32.BAT"
cl >nul 2>&1
if errorlevel 9009 (echo ERROR: cl.exe not found - run from a VC6 command prompt or set VC6DIR & exit /b 1)
if exist "%PSDKDIR%\SetEnv.Cmd" (
  call "%PSDKDIR%\SetEnv.Cmd" /XP32 /RETAIL
) else (
  echo WARNING: Platform SDK not found in "%PSDKDIR%" - set PSDKDIR. VC6's own headers are too old for PHP 5.2.
)
cl 2>&1 | find "Version 12.00" >nul
if errorlevel 1 (echo ERROR: cl.exe is not Visual C++ 6.0 ^(12.00^) & exit /b 1)
mc -? >nul 2>&1
if errorlevel 9009 (echo ERROR: mc.exe ^(message compiler^) not found - it comes with the Platform SDK & exit /b 1)
call :log "toolchain ok"

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
call buildconf.bat >>"%LOG%" 2>&1 || (popd & exit /b 1)
set "CFG=--with-php-build=%PB% --enable-cli-win32"
if /i "%FL%"=="ts" (set "CFG=!CFG! --enable-isapi") else (set "CFG=!CFG! --disable-zts")
if /i "%FL%"=="ts" if defined APACHE22 set "CFG=!CFG! --enable-apache2-2handler --with-apache-includes=%APACHE22%\include --with-apache-libs=%APACHE22%\lib"
call :log "PHP %FL%: configure !CFG!"
cscript //nologo configure.js !CFG! > "%KIT%\configure-%FL%.log" 2>&1 || (popd & exit /b 1)
call :log "PHP %FL%: nmake"
nmake /nologo >> "%KIT%\nmake-%FL%.log" 2>&1 || (popd & echo see %KIT%\nmake-%FL%.log & exit /b 1)
popd

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

:log
echo [%TIME:~0,8%] %~1
echo [%TIME:~0,8%] %~1 >> "%LOG%"
exit /b 0

:fail
echo BUILD FAILED - see %LOG% ^(and configure-*.log / nmake-*.log^)
exit /b 1
