--TEST--
CVE-2011-1398: header() rejects a bare CR and NUL bytes
--INI--
display_errors=1
html_errors=0
--FILE--
<?php
ob_start(); // the warnings must not send the headers
header("X-A: one\rtwo");
header("X-B: one\0two");
header("X-C: folded\r\n continuation");
echo "done\n";
?>
--EXPECTF--
%AWarning: Header may not contain more than a single header, new line detected in %s on line 3

Warning: Header may not contain NUL bytes in %s on line 4
done
