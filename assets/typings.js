document.addEventListener('DOMContentLoaded', () => {
	if (document.getElementById("typed")) {
		var typed1 = new Typed('#typed', {
			stringsElement: '#typed-strings',
			showCursor: false,
			typeSpeed: 10,
			backSpeed: 10,
			startDelay: 50,
		});
	};

});