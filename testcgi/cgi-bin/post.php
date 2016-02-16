<!doctype html>
<html>
<body>
<?php



if (isset($_POST['a'])) {
	?>
	<p>you entered: <?php echo htmlentities($_POST['a']) ?></p>
	<?php
} else {
	?>
	<form method="POST">
	<input type="text" name="a" />
	<button>Submit</button>
	</form>
	<?php
}
?>
</body>
</html>
