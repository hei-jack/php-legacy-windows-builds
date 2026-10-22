<?php
/* Compares the FAILED TEST SUMMARY of two run-tests.php logs (official vs rebuilt).
 * Tests that fail only with the rebuilt PHP are listed; the expected ones (behaviour changed
 * on purpose by the backports) are reported separately. PHP 5.2 syntax.
 *
 * usage: php -n compare-fails.php <official.log> <rebuilt.log>
 */
function fails($log)
{
	$in = false;
	$list = array();
	foreach (file($log) as $line) {
		if (strpos($line, 'FAILED TEST SUMMARY') === 0) {
			$in = true;
			continue;
		}
		if ($in && strpos($line, '=====') === 0 && $list) {
			break;
		}
		if ($in && preg_match('/\[([^\]]+\.phpt)\]/', $line, $m)) {
			$list[str_replace('\\', '/', $m[1])] = true;
		}
	}
	return $list;
}

/* fail with the backports by design (see php52/README.md) */
$expected = array();

$official = fails($argv[1]);
$rebuilt = fails($argv[2]);
$new = array_diff_key($rebuilt, $official);
$fixed = array_diff_key($official, $rebuilt);
printf("official: %d failed, rebuilt: %d failed, %d only in rebuilt, %d only in official\n",
	count($official), count($rebuilt), count($new), count($fixed));
$bad = 0;
foreach (array_keys($new) as $t) {
	$isExpected = false;
	foreach ($expected as $e) {
		if (substr($t, -strlen($e)) === $e) {
			$isExpected = true;
		}
	}
	echo $isExpected ? '  expected: ' : '  NEW FAILURE: ', $t, "\n";
	if (!$isExpected) {
		$bad++;
	}
}
foreach (array_keys($fixed) as $t) {
	echo '  passes now: ', $t, "\n";
}
exit($bad ? 1 : 0);
