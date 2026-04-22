// Render each .research-main <table> as a sibling <dl class="table-cards"> of
// per-row cards. CSS media queries swap between the two at the mobile
// breakpoint; both stay in the DOM so rotation works without a resize
// listener.
(function () {
  function cardsFromTable(table) {
    var headers = Array.prototype.map.call(
      table.querySelectorAll('thead th'),
      function (th) { return th.innerHTML; }
    );
    if (headers.length === 0) return null;

    var wrap = document.createElement('div');
    wrap.className = 'table-cards';

    Array.prototype.forEach.call(table.querySelectorAll('tbody tr'), function (tr) {
      var dl = document.createElement('dl');
      dl.className = 'table-card';
      Array.prototype.forEach.call(tr.children, function (td, i) {
        var dt = document.createElement('dt');
        dt.innerHTML = headers[i] || '';
        var dd = document.createElement('dd');
        dd.innerHTML = td.innerHTML;
        dl.appendChild(dt);
        dl.appendChild(dd);
      });
      wrap.appendChild(dl);
    });
    return wrap;
  }

  function transform() {
    var tables = document.querySelectorAll('.research-main table');
    Array.prototype.forEach.call(tables, function (table) {
      if (table.closest('.table-cards')) return;
      var cards = cardsFromTable(table);
      if (cards) table.parentNode.insertBefore(cards, table.nextSibling);
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', transform);
  } else {
    transform();
  }
})();
