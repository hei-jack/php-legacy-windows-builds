<#
.SYNOPSIS
  Prepares the PHP 5.2.17 VC6 build kit on a modern Windows machine.

.DESCRIPTION
  The VC6 build VM (often Windows XP/2003/7) usually can't download over modern TLS, so this
  script does everything that needs the network or git, and writes a self-contained folder to
  copy to the VM:

    <Out>\src\php-5.2.17          release tarball + php52\patches applied
    <Out>\deps\zlib-*, libiconv-*, libxml2-*   dependency sources (built on the VM)
    <Out>\official\ts, \nts       official php-5.2.17 VC6 zips (their ext\*.dll are reused)
    <Out>\apache22\include, \lib  Apache 2.2 headers and import libraries (for php5apache2_2.dll)
    <Out>\kit\                    build.cmd and the check scripts
    <Out>\tests\                  targeted .phpt tests

  Every download is checked against a pinned SHA-256.
  Needs: PowerShell 5.1+, Git for Windows (git, and its tar/xz).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File php52\kit\fetch.ps1 -Out C:\php52kit
#>
param(
    [string]$Out = 'C:\php52kit',
    [ValidateSet('2.9.14')]
    [string]$LibxmlVersion = '2.9.14'
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$php52 = Split-Path -Parent $here
if ($Out -match '\s') { throw "Out must not contain spaces (nmake/cscript paths): $Out" }

$git = (Get-Command git -ErrorAction Stop).Source
$gitRoot = Split-Path -Parent (Split-Path -Parent $git)          # ...\Git
$tar = Join-Path $gitRoot 'usr\bin\tar.exe'                      # GNU tar, uses xz/gzip from usr\bin
if (-not (Test-Path $tar)) { throw "GNU tar not found at $tar (comes with Git for Windows)" }
$env:PATH = (Join-Path $gitRoot 'usr\bin') + ';' + $env:PATH

$downloads = @(
    @{ Name = 'php-5.2.17.tar.gz';                Url = 'https://museum.php.net/php5/php-5.2.17.tar.gz';
       Sha = '1abe07c1fdd64184708a3ba179abcfcca5662a4e0d2037eb2748b75abc42e767' }
    @{ Name = 'php-5.2.17-Win32-VC6-x86.zip';     Url = 'https://windows.php.net/downloads/releases/archives/php-5.2.17-Win32-VC6-x86.zip';
       Sha = '18951f4a6282b5a34afa11e07249d336169bc06a98dba88bd5cff72109105ca0' }
    @{ Name = 'php-5.2.17-nts-Win32-VC6-x86.zip'; Url = 'https://windows.php.net/downloads/releases/archives/php-5.2.17-nts-Win32-VC6-x86.zip';
       Sha = 'c20433d1fbf7d2bcabe591757b8dcdb00a7477f191e091d95d4f774a601d790b' }
    @{ Name = 'zlib-1.3.1.tar.gz';                Url = 'https://zlib.net/fossils/zlib-1.3.1.tar.gz';
       Sha = '9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23' }
    @{ Name = 'libiconv-1.11.1.tar.gz';           Url = 'https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.11.1.tar.gz';
       Sha = 'e78c347a1a0cb15f2648519e9799151f4b4a934b61ad9ee7424478efe2b8257f' }
    @{ Name = 'libxml2-2.9.14.tar.xz';            Url = 'https://download.gnome.org/sources/libxml2/2.9/libxml2-2.9.14.tar.xz';
       Sha = '60d74a257d1ccec0475e749cba2f21559e48139efba6ff28224357c7c798dfee' }
    # Apache's own 2.2 Win32 build (VC6): its headers and import libraries build php5apache2_2.dll
    # (MD5/SHA-1 match archive.apache.org's .md5/.sha1 files)
    @{ Name = 'httpd-2.2.25-win32-x86-no_ssl.msi'; Url = 'https://archive.apache.org/dist/httpd/binaries/win32/httpd-2.2.25-win32-x86-no_ssl.msi';
       Sha = 'cee8800d2f9f15dad1e3d1e7f2d2e1b331b5a39461fe6855d63c94c8f8baef9c' }
)

function Step($msg) { Write-Host "[$(Get-Date -Format HH:mm:ss)] $msg" }

New-Item -ItemType Directory -Force "$Out\downloads", "$Out\src", "$Out\deps", "$Out\official", "$Out\kit", "$Out\tests" | Out-Null

foreach ($d in $downloads) {
    $f = Join-Path "$Out\downloads" $d.Name
    if (-not (Test-Path $f)) {
        Step "downloading $($d.Name)"
        Invoke-WebRequest -UseBasicParsing -Uri $d.Url -OutFile "$f.part"
        Move-Item -Force "$f.part" $f
    }
    $sha = (Get-FileHash -Algorithm SHA256 $f).Hash.ToLower()
    if ($sha -ne $d.Sha) { Remove-Item $f; throw "SHA-256 mismatch for $($d.Name): $sha" }
}
Step 'all downloads verified'

function Untar($archive, $dest) {
    Push-Location $dest
    try { & $tar --force-local -xf $archive; if ($LASTEXITCODE) { throw "tar failed on $archive" } }
    finally { Pop-Location }
}

# PHP source: fresh tarball + the patch series, in order
$src = "$Out\src\php-5.2.17"
if (Test-Path $src) { Remove-Item -Recurse -Force $src }
Step 'extracting php-5.2.17'
Untar "$Out\downloads\php-5.2.17.tar.gz" "$Out\src"
$env:GIT_CEILING_DIRECTORIES = Split-Path -Parent $src
foreach ($p in Get-ChildItem "$php52\patches\*.patch" | Sort-Object Name) {
    & $git -C $src apply --whitespace=nowarn $p.FullName
    if ($LASTEXITCODE) { throw "patch failed: $($p.Name)" }
    Step "applied $($p.Name)"
}
# The generated scanner must stay newer than its .re (the Windows build has no re2c rule, but be safe)
(Get-Item "$src\ext\standard\var_unserializer.c").LastWriteTime = Get-Date

# Dependencies
foreach ($a in 'zlib-1.3.1.tar.gz', 'libiconv-1.11.1.tar.gz', "libxml2-$LibxmlVersion.tar.xz") {
    $dir = Join-Path "$Out\deps" ($a -replace '\.tar\.(gz|xz)$', '')
    if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
    Step "extracting $a"
    Untar "$Out\downloads\$a" "$Out\deps"
}
# VC6 has no "ULL" suffix (it spells 64-bit constants ui64): the only such constant in libxml2 2.9.14
$ts = "$Out\deps\libxml2-$LibxmlVersion\timsort.h"
(Get-Content -Raw $ts).Replace('(1ULL << shift)', '(((uint64_t)1) << shift)') | Set-Content -NoNewline $ts

# Official binaries (their extensions are reused as is)
foreach ($flavor in @(@{ Dir = 'ts'; Zip = 'php-5.2.17-Win32-VC6-x86.zip' }, @{ Dir = 'nts'; Zip = 'php-5.2.17-nts-Win32-VC6-x86.zip' })) {
    $dest = "$Out\official\$($flavor.Dir)"
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    Expand-Archive -Path "$Out\downloads\$($flavor.Zip)" -DestinationPath $dest
}
Step 'official 5.2.17 zips extracted'

# Apache 2.2 headers and import libraries: an administrative install unpacks the MSI without
# installing Apache
$ax = "$Out\downloads\apache22-msi"
if (Test-Path $ax) { Remove-Item -Recurse -Force $ax }
$p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList '/a', "`"$Out\downloads\httpd-2.2.25-win32-x86-no_ssl.msi`"", '/qn', "TARGETDIR=`"$ax`""
if ($p.ExitCode -ne 0) { throw "msiexec /a failed ($($p.ExitCode))" }
$apache = Get-ChildItem -Recurse -Directory $ax -Filter Apache2.2 | Select-Object -First 1
if (-not $apache -or -not (Test-Path "$($apache.FullName)\include\httpd.h")) { throw 'Apache 2.2 headers not found in the MSI' }
if (Test-Path "$Out\apache22") { Remove-Item -Recurse -Force "$Out\apache22" }
New-Item -ItemType Directory -Force "$Out\apache22\lib" | Out-Null
Copy-Item -Recurse "$($apache.FullName)\include" "$Out\apache22\include"
foreach ($lib in 'libhttpd.lib', 'libapr-1.lib', 'libaprutil-1.lib') { Copy-Item "$($apache.FullName)\lib\$lib" "$Out\apache22\lib\" }
Remove-Item -Recurse -Force $ax
Step 'Apache 2.2.25 headers and libraries extracted'

Copy-Item -Recurse -Force "$here\*" "$Out\kit\"
Copy-Item -Force "$php52\tests\*.phpt" "$Out\tests\"

Get-ChildItem "$Out\downloads" | Get-FileHash -Algorithm SHA256 |
    ForEach-Object { '{0}  {1}' -f $_.Hash.ToLower(), (Split-Path -Leaf $_.Path) } |
    Set-Content "$Out\SHA256SUMS.txt"
Step "kit ready in $Out - copy that folder to the VC6 VM (same path) and run kit\build.cmd there"
