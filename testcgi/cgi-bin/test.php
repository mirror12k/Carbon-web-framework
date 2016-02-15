<?php


function redirect($location, $permanent=FALSE) {
	if ($permanent) {
		header('Location: ' . $location, TRUE, 301);
	} else {
		header('Location: ' . $location, TRUE, 303);
	}
	die();
}

redirect('/asdf.php');


