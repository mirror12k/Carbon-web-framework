<!doctype html>
<html>
<body>
<?php



if (isset($_GET['a'])) {
	?>
	<p>you entered: <?php echo htmlentities($_GET['a']) ?></p>
	<?php
} else {
	?>
	<form method="GET">
	<input type="text" name="a" />
	<button>Submit</button>
	</form>
	<?php
}
?>
</body>
</html>
