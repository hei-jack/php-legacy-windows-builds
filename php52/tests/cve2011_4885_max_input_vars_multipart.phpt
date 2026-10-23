--TEST--
CVE-2011-4885: max_input_vars limits multipart form fields
--INI--
display_startup_errors=1
max_input_vars=2
max_multipart_body_parts=100
display_errors=1
html_errors=0
--POST_RAW--
Content-Type: multipart/form-data; boundary=bnd123
--bnd123
Content-Disposition: form-data; name="a"

1
--bnd123
Content-Disposition: form-data; name="b"

2
--bnd123
Content-Disposition: form-data; name="c"

3
--bnd123--
--FILE--
<?php
var_dump(array_keys($_POST));
?>
--EXPECTF--
%AInput variables exceeded 2. To increase the limit change max_input_vars in php.ini.%A
array(2) {
  [0]=>
  string(1) "a"
  [1]=>
  string(1) "b"
}
