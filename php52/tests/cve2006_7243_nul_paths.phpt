--TEST--
CVE-2006-7243 and follow-ups: paths containing a NUL byte are rejected, not truncated
--INI--
display_errors=0
--FILE--
<?php
$d = dirname(__FILE__) . '/nulpaths';
@mkdir($d);
file_put_contents("$d/ok.txt", "SECRET");
file_put_contents("$d/ok.php", "<?php echo 'INCLUDED';");
file_put_contents("$d/ok.ini", "a=1\n");
file_put_contents("$d/ok.xml", "<r>x</r>");
$n = "\0.jpg";
$bad = array();
function t($name, $truncated) { global $bad; if ($truncated) $bad[] = $name; }

ob_start(); include "$d/ok.php$n"; t('include', strpos(ob_get_clean(), 'INCLUDED') !== false);
t('fopen', ($h = fopen("$d/ok.txt$n", 'r')) && fread($h, 6) === 'SECRET');
t('file', ($r = file("$d/ok.txt$n")) && $r[0] === 'SECRET');
t('file_get_contents', file_get_contents("$d/ok.txt$n") === 'SECRET');
ob_start(); readfile("$d/ok.txt$n"); t('readfile', ob_get_clean() === 'SECRET');
t('file_put_contents', file_put_contents("$d/new1.txt$n", 'x') && file_exists("$d/new1.txt"));
t('copy', copy("$d/ok.txt$n", "$d/copy.txt") || copy("$d/ok.txt", "$d/copy2.txt$n"));
file_put_contents("$d/ren.txt", 'r'); t('rename', rename("$d/ren.txt$n", "$d/ren2.txt") || rename("$d/ren.txt", "$d/ren3.txt$n"));
file_put_contents("$d/del.txt", 'd'); t('unlink', unlink("$d/del.txt$n") || !file_exists("$d/del.txt"));
t('mkdir', mkdir("$d/newdir$n") || is_dir("$d/newdir"));
@mkdir("$d/rmd"); t('rmdir', rmdir("$d/rmd$n") || !is_dir("$d/rmd"));
t('tempnam', (bool) tempnam("$d$n", 'x'));
t('realpath', realpath("$d/ok.txt$n") !== false);
$cwd = getcwd(); t('chdir', chdir("$d$n")); chdir($cwd);
t('opendir', (bool) opendir("$d$n"));
t('scandir', (bool) scandir("$d$n"));
t('file_exists', file_exists("$d/ok.txt$n"));
t('is_file', is_file("$d/ok.txt$n"));
t('filesize', filesize("$d/ok.txt$n") === 6);
t('touch', touch("$d/touched$n") || file_exists("$d/touched"));
t('chmod', chmod("$d/ok.txt$n", 0644));
t('disk_free_space', disk_free_space("$d$n") > 0);
t('highlight_file', (bool) highlight_file("$d/ok.php$n", true));
t('php_strip_whitespace', strpos(php_strip_whitespace("$d/ok.php$n"), 'INCLUDED') !== false);
t('parse_ini_file', ($r = parse_ini_file("$d/ok.ini$n")) && isset($r['a']));
t('error_log', error_log("logged", 3, "$d/log.txt$n") && file_exists("$d/log.txt"));
$old = get_include_path(); t('set_include_path', set_include_path("$d$n") !== false); set_include_path($old);
t('md5_file', md5_file("$d/ok.txt$n") === md5('SECRET'));
t('sha1_file', sha1_file("$d/ok.txt$n") === sha1('SECRET'));
t('getimagesize', getimagesize("$d/ok.txt$n") !== false || error_get_last() === null);
if (function_exists('hash_file')) t('hash_file', hash_file('md5', "$d/ok.txt$n") === md5('SECRET'));
if (function_exists('simplexml_load_file')) t('simplexml_load_file', (bool) simplexml_load_file("$d/ok.xml$n"));
if (class_exists('DOMDocument')) {
	$x = new DOMDocument; t('DOMDocument::load', (bool) $x->load("$d/ok.xml$n"));
	$x = new DOMDocument; $x->loadXML('<r/>'); t('DOMDocument::save', $x->save("$d/saved.xml$n") && file_exists("$d/saved.xml"));
}
if (class_exists('XMLReader')) { $r = new XMLReader; t('XMLReader::open', (bool) $r->open("$d/ok.xml$n")); }
if (function_exists('xmlwriter_open_uri')) t('xmlwriter_open_uri', xmlwriter_open_uri("$d/w.xml$n") && file_exists("$d/w.xml"));
if (function_exists('gzopen')) t('gzopen', (bool) gzopen("$d/ok.txt$n", 'r'));
try { new SplFileObject("$d/ok.txt$n"); t('SplFileObject', true); } catch (Exception $e) { }
try { new DirectoryIterator("$d$n"); t('DirectoryIterator', true); } catch (Exception $e) { }
if (function_exists('symlink') && substr(PHP_OS, 0, 3) != 'WIN') {
	t('symlink', symlink("$d/ok.txt", "$d/sl$n") || is_link("$d/sl"));
	symlink("$d/ok.txt", "$d/sl2"); t('readlink', readlink("$d/sl2$n") === "$d/ok.txt");
}

echo $bad ? 'TRUNCATED: ' . implode(', ', $bad) : 'all rejected', "\n";
echo file_get_contents("$d/ok.txt"), "\n";
?>
--CLEAN--
<?php
$d = dirname(__FILE__) . '/nulpaths';
foreach ((array) glob("$d/*") as $f) { is_dir($f) ? @rmdir($f) : @unlink($f); }
@rmdir($d);
?>
--EXPECT--
all rejected
SECRET
