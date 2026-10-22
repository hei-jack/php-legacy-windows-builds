--TEST--
CVE-2026-109619: user error and exception handlers work normally within a request
--FILE--
<?php
function eh($no, $str) { echo "error handler: $str\n"; return true; }
function xh($e) { echo "exception handler: ", $e->getMessage(), "\n"; }
set_error_handler("eh");
set_exception_handler("xh");
echo $undefined_var;
trigger_error("custom", E_USER_NOTICE);
throw new Exception("boom");
?>
--EXPECT--
error handler: Undefined variable: undefined_var
error handler: custom
exception handler: boom
