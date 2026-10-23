@echo off
rem Checks the builds in <kit>\dist against the official PHP 5.2.17 binaries:
rem   1. php5ts.dll/php5.dll exports everything the official extensions/SAPIs import
rem   2. every official ext\php_*.dll loads with the rebuilt PHP whenever it loads with the official one
rem   3. targeted tests (kit\..\tests): rebuilt must pass all; official is shown for reference
rem   4. with "full": Zend, tests, ext\standard, ext\session suites on both, compared
rem usage: C:\php52kit\kit\check.cmd [full]
setlocal EnableExtensions
for %%I in ("%~dp0..") do set "KIT=%%~fI"
set FULL=%~1
rem dumpbin (VC6) is needed for the export check
if not defined VC6DIR set "VC6DIR=C:\Program Files\Microsoft Visual Studio\VC98"
dumpbin >nul 2>&1
if errorlevel 9009 if exist "%VC6DIR%\Bin\VCVARS32.BAT" call "%VC6DIR%\Bin\VCVARS32.BAT" >nul
set FAIL=0
set CHECKED=0
for %%F in (ts nts) do call :check %%F
if %CHECKED%==0 (echo ERROR: no build in %KIT%\dist - run kit\build.cmd first & exit /b 1)
if %FAIL%==0 (echo. & echo ALL CHECKS PASSED) else (echo. & echo SOME CHECKS FAILED - see above)
exit /b %FAIL%

:check
set "DIST=%KIT%\dist\php-5.2.17-cve2026-%1-Win32-VC6-x86"
if not exist "%DIST%\php.exe" exit /b 0
set /a CHECKED+=1
if /i "%1"=="ts" (set "DLL=php5ts.dll" & set "OFF=%KIT%\official\ts") else (set "DLL=php5.dll" & set "OFF=%KIT%\official\nts")
set "SRC=%KIT%\build-%1\php-5.2.17"
echo.
echo ===================== %1: %DIST%
"%DIST%\php.exe" -n -v

echo --- ABI
dumpbin /nologo /exports "%DIST%\%DLL%" > "%KIT%\exports-%1.txt"
"%DIST%\php.exe" -n "%KIT%\kit\abi-check.php" "%KIT%\exports-%1.txt" "%KIT%\kit\abi\official-5.2.17-%1-imports.txt" || set FAIL=1

echo --- extensions
"%DIST%\php.exe" -n "%KIT%\kit\ext-check.php" "%DIST%" "%OFF%" || set FAIL=1

echo --- targeted tests
call :tests targeted-%1 "%DIST%" "%KIT%\tests" || set FAIL=1
call :tests targeted-%1-official "%OFF%" "%KIT%\tests"
if /i not "%FULL%"=="full" exit /b 0

echo --- full suites (slow)
call :tests full-%1 "%DIST%" "Zend tests ext\standard\tests ext\session"
call :tests full-%1-official "%OFF%" "Zend tests ext\standard\tests ext\session"
"%DIST%\php.exe" -n "%KIT%\kit\compare-fails.php" "%KIT%\results\full-%1-official.log" "%KIT%\results\full-%1.log" || set FAIL=1
exit /b 0

rem :tests <label> <php dir> <test dirs, relative to the source tree, or an absolute dir>
:tests
set "OUTDIR=%KIT%\results"
if not exist "%OUTDIR%" mkdir "%OUTDIR%"
set "TEST_PHP_EXECUTABLE=%~2\php.exe"
set "TEST_PHP_CGI_EXECUTABLE=%~2\php-cgi.exe"
set NO_INTERACTION=1
set REPORT_EXIT_STATUS=1
rem run-tests writes next to the tests: run on a private copy of the tree
set "RT=%KIT%\testrun\%1"
if exist "%RT%" rmdir /s /q "%RT%"
xcopy /e /i /q /k "%SRC%" "%RT%" >nul
xcopy /i /q /y "%KIT%\tests\*.phpt" "%RT%\cve-tests\" >nul
pushd "%RT%"
rem PHP 5.2 on Windows shows a MessageBox for startup warnings when display_startup_errors is on,
rem which run-tests.php sets; tests that pass bad ini values would stop on a dialog. Turn it off
rem in this private copy (same for the official and the rebuilt runs, so the comparison holds).
"%~2\php.exe" -n -r "$f='run-tests.php'; file_put_contents($f, str_replace(\"'display_startup_errors=1'\", \"'display_startup_errors=0'\", file_get_contents($f)));"
set "DIRS=%~3"
if /i "%DIRS%"=="%KIT%\tests" set DIRS=cve-tests
"%~2\php.exe" -n run-tests.php %DIRS% > "%OUTDIR%\%1.log" 2>&1
set RC=%ERRORLEVEL%
popd
findstr /b /c:"Tests passed" /c:"Tests failed" "%OUTDIR%\%1.log"
exit /b %RC%
