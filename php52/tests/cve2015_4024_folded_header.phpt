--TEST--
CVE-2015-4024: folded multipart headers are still joined correctly
--INI--
file_uploads=1
--POST_RAW--
Content-Type: multipart/form-data; boundary=bnd123
--bnd123
Content-Disposition: form-data;
 name="folded"

value
--bnd123
Content-Disposition: form-data; name="up";
	filename="f.txt"
Content-Type: text/plain

abc
--bnd123--
--FILE--
<?php
var_dump($_POST, $_FILES['up']['name'], $_FILES['up']['size']);
?>
--EXPECT--
array(1) {
  ["folded"]=>
  string(5) "value"
}
string(5) "f.txt"
int(3)
