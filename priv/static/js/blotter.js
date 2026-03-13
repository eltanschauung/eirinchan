function toggleNews() {
  var newsBlotter = document.querySelector('#blotterContainer .news-blotter');
  if (!newsBlotter) return;
  newsBlotter.style.display = newsBlotter.style.display === 'block' ? 'none' : 'block';
}

window.toggleNews = window.toggleNews || toggleNews;
