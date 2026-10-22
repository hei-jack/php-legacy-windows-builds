--TEST--
CVE-2011-4885: max_input_vars limits GET, POST and COOKIE variables
--INI--
max_input_vars=5
display_errors=1
display_startup_errors=0
html_errors=0
error_reporting=E_ALL
--GET--
g1=1&g2=2&g3=3&g4=4&g5=5&g6=6&g7=7
--POST--
p1=1&p2=2&p3=3&p4=4&p5=5&p6=6&p7=7
--COOKIE--
c1=1; c2=2; c3=3; c4=4; c5=5; c6=6
--FILE--
<?php
/* Startup warnings are not displayed here: displaying one sends output, and
 * PHP 5.2/5.3 then skip POST parsing altogether (SG(headers_sent)). */
var_dump(count($_GET), count($_POST), count($_COOKIE));
$e = error_get_last();
echo $e['message'], "\n";
?>
--EXPECT--
int(5)
int(5)
int(5)
Unknown: Input variables exceeded 5. To increase the limit change max_input_vars in php.ini.
