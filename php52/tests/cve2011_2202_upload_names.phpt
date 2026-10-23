--TEST--
CVE-2011-2202: uploaded file names keep their first character (with magic_quotes_gpc on)
--INI--
file_uploads=1
magic_quotes_gpc=1
--POST_RAW--
Content-Type: multipart/form-data; boundary=bnd123
--bnd123
Content-Disposition: form-data; name="a"; filename="f.txt"

1
--bnd123
Content-Disposition: form-data; name="b"; filename="C:\dir\g.txt"

2
--bnd123
Content-Disposition: form-data; name="c"; filename="/abs/h.txt"

3
--bnd123--
--FILE--
<?php
foreach ($_FILES as $k => $f) echo $k, ': ', $f['name'], "\n";
?>
--EXPECT--
a: f.txt
b: g.txt
c: h.txt
