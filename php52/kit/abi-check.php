<?php
/* Checks that a rebuilt php5ts.dll / php5.dll exports every symbol the official PHP 5.2.17
 * extensions and SAPIs import from it (lists in kit\abi\, made with objdump -p from the
 * official zips). PHP 5.2 syntax on purpose: it runs with the freshly built php.exe.
 *
 * usage: php -n abi-check.php <dumpbin /exports output> <official-*-imports.txt>
 */
if ($argc != 3) {
	fwrite(STDERR, "usage: php -n abi-check.php <exports.txt> <imports.txt>\n");
	exit(2);
}
$exports = array();
foreach (file($argv[1]) as $line) {
	/* dumpbin: "    ordinal hint RVA      name" (RVA missing for forwarders) */
	if (preg_match('/^\s+\d+\s+[0-9A-F]+\s+(?:[0-9A-F]{8}\s+)?(\S+)/', $line, $m)) {
		$exports[$m[1]] = true;
	}
}
if (count($exports) < 1000) {
	fwrite(STDERR, "only " . count($exports) . " exports parsed from {$argv[1]} - is it dumpbin /exports output?\n");
	exit(2);
}
$missing = array();
$needed = 0;
foreach (file($argv[2]) as $sym) {
	$sym = trim($sym);
	if ($sym === '') {
		continue;
	}
	$needed++;
	if (!isset($exports[$sym])) {
		$missing[] = $sym;
	}
}
printf("%d exports, %d symbols needed by the official extensions/SAPIs, %d missing\n", count($exports), $needed, count($missing));
foreach ($missing as $sym) {
	echo "  MISSING: $sym\n";
}
exit($missing ? 1 : 0);
