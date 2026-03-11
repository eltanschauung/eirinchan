if (active_page === 'thread' || active_page === 'index' || active_page === 'catalog' || active_page === 'ukko') {
document.addEventListener('DOMContentLoaded', function() {

        // add options panel item
        if (window.Options && Options.get_tab('general')) {
                Options.extend_tab('general', '<label id="add-nav-arrows"><input type="checkbox">' + _('Display navigation arrows') + '</label>');

                $('#add-nav-arrows>input').on('click', function() {
                        if ($('#add-nav-arrows>input').is(':checked')) {
                                localStorage.navarrows = 'true';
                        } else {
                                localStorage.navarrows = 'false';
                        }
                        //Refresh
                        location.reload();
                });

                if (typeof localStorage.navarrows === 'undefined') localStorage.navarrows = 'true';
                if (localStorage.navarrows === 'true') $('#add-nav-arrows>input').prop('checked', true);
        }

if (localStorage.navarrows == 'false' || !(window.URL.createObjectURL && window.File))
        return;

    'use strict';

	// Create top arrow
	var topArrow = document.createElement('div');
	topArrow.classList.add('navarrow');
	topArrow.innerHTML = '<img src="/reisen_up.png" alt="Scroll to top" width="80%" height="auto">';  // ← replaces SVG
	topArrow.style.cssText = 'position: fixed; bottom: 100px; right: 20px; font-size: 24px; cursor: pointer;';

	// Create bottom arrow
	var bottomArrow = document.createElement('div');
	bottomArrow.classList.add('navarrow');
	bottomArrow.innerHTML = '<img src="/tewi_down.png" alt="Scroll to bottom" width="80%" height="auto">';  // ← replaces SVG\
	bottomArrow.style.cssText = 'position: fixed; bottom: 30px; right: 20px; font-size: 24px; cursor: pointer;';

    // Add click event for top arrow
    topArrow.addEventListener('click', function() {
        document.body.scrollTop = 0; // For Safari
        document.documentElement.scrollTop = 0; // For Chrome, Firefox, IE, and Opera
    });

    // Add click event for bottom arrow
    bottomArrow.addEventListener('click', function() {
        var bottomElement = document.querySelector('a[name="bottom"]');
        if (bottomElement) {
            bottomElement.scrollIntoView({ behavior: 'auto' });
        }
    });

    // Append arrows to the body
    document.body.appendChild(topArrow);
    document.body.appendChild(bottomArrow);
})};
