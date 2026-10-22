<?php
/* Loads every official ext\php_*.dll, one at a time, with the rebuilt php.exe and with the
 * official php.exe, and compares: an extension must load in the rebuilt PHP whenever it loads
 * in the official one (some need client DLLs or services that are not there - those fail in
 * both). Also compares the built-in module lists (php -m).
 * PHP 5.2 syntax on purpose.
 *
 * usage: php -n ext-check.php <rebuilt dist dir> <official dir>
 */
if ($argc != 3) {
	fwrite(STDERR, "usage: php -n ext-check.php <dist dir> <official dir>\n");
	exit(2);
}
$dist = rtrim($argv[1], '\\/');
$official = rtrim($argv[2], '\\/');

$basePath = getenv('PATH');

/* Paths are known to be free of spaces (fetch.ps1 checks), so nothing is quoted: PHP 5.2's exec()
 * hands the line to cmd /c, which mangles nested quotes. */
function run_php($dir, $args)
{
	global $basePath;
	/* the extension's own dependencies (libmysql.dll, ...) live next to php.exe */
	putenv('PATH=' . $dir . ';' . $basePath);
	$out = array();
	exec($dir . '\\php.exe -n ' . $args . ' 2>&1', $out, $rc);
	return array($rc, trim(implode("\n", $out)));
}

$fail = 0;

list($rc, $ours) = run_php($dist, '-m');
list($rc2, $theirs) = run_php($official, '-m');
if ($ours !== $theirs) {
	echo "BUILT-IN MODULES DIFFER\n--- official\n$theirs\n--- rebuilt\n$ours\n";
	$fail = 1;
} else {
	echo "built-in modules: same as official (" . count(explode("\n", $ours)) . " lines)\n";
}

function loaded($out)
{
	return strpos($out, 'LOADED') !== false
		&& strpos($out, 'Unable to load') === false
		&& strpos($out, 'compiled with') === false; /* API / build id mismatch */
}

function ext_args($dir, $name)
{
	$args = '-d extension_dir=' . $dir . '\\ext';
	/* extensions that need another one loaded first */
	if (strpos($name, 'php_pdo_') === 0 || $name === 'php_sqlite.dll') {
		$args .= ' -d extension=php_pdo.dll';
	} else if ($name === 'php_exif.dll') {
		$args .= ' -d extension=php_mbstring.dll';
	}
	return $args . ' -d extension=' . $name;
}

$probe = '-r "echo \'LOADED\';"';
foreach (glob($dist . '\\ext\\php_*.dll') as $dll) {
	$name = basename($dll);
	list($rc, $o) = run_php($dist, ext_args($dist, $name) . ' ' . $probe);
	list($rc2, $t) = run_php($official, ext_args($official, $name) . ' ' . $probe);
	$okOurs = loaded($o);
	$okTheirs = loaded($t);
	if ($okOurs && $okTheirs) {
		$state = 'ok';
	} else if (!$okOurs && !$okTheirs) {
		$state = 'fails in both (missing dependency?)';
	} else if ($okTheirs) {
		$state = 'REGRESSION: loads in official only';
		$fail = 1;
	} else {
		$state = 'loads in rebuilt only';
	}
	printf("%-28s %s\n", $name, $state);
	if ($state !== 'ok' && !$okOurs) {
		echo '    ', str_replace("\n", "\n    ", $o), "\n";
	}
}
exit($fail);
