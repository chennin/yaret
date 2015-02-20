// Cookie functions
function createCookie(name,value,days) {
  if (days) {
    var date = new Date();
    date.setTime(date.getTime()+(days*24*60*60*1000));
    var expires = "; expires="+date.toGMTString();
  }
  else var expires = "";
  document.cookie = name+"="+value+expires+"; path=/";
}
function readCookie(name) {
  var nameEQ = name + "=";
  var ca = document.cookie.split(';');
  for(var i=0;i < ca.length;i++) {
    var c = ca[i];
    while (c.charAt(0)==' ') c = c.substring(1,c.length);
    if (c.indexOf(nameEQ) == 0) return c.substring(nameEQ.length,c.length);
  }
  return null;
}
function eraseCookie(name) {
        createCookie(name,"",-1);
}
function hidetr(id,store) {
        var color = document.getElementById(id).style.color;
        if (color != "rgb(76, 76, 76)") {
                document.getElementById(id).style.color = "#4C4C4C";
                document.getElementById(id).oldColor = color;

                var children = document.getElementById(id).getElementsByTagName("TD");
                for (var i=0; i<children.length; i++) {
                        children[i].oldColor = children[i].style.color;
                        children[i].style.color = "#4C4C4C";
                }
                if (store == "true") { sessionStorage.setItem(id,"hide"); }
        }
        else {
                document.getElementById(id).style.color = document.getElementById(id).oldColor;
                var children = document.getElementById(id).getElementsByTagName("TD");
                for (var i=0; i<children.length; i++) {
                        children[i].style.color = children[i].oldColor;
                }
                sessionStorage.removeItem(id);
        }
}
function initialize() {
  // Add handlers to th's to set sort col pref
  var headers = ["Event", "Shard", "Zone", "Age"]; 
  var headerfuncs = [];
  function clickheader(i) {
    return function() { createCookie("sort",i,365); };
  }
  for (var h=0; h<headers.length; h++) {
    var elements = document.getElementsByClassName(headers[h]);  
    headerfuncs[h] = clickheader(headers[h]);
    for (var i=0; i<elements.length; i++) { 
      elements[i].addEventListener('click', headerfuncs[h]);
    }
  }
  // If sort col pref is set, sort on page load
  var sortpref = readCookie('sort');
  if (sortpref) {
    var sortname = sortpref + "";
    var elements = document.getElementsByClassName(sortname);
    for (var i=0; i<elements.length; i++) {
      sorttable.innerSortFunction.apply(elements[i], []);
    }
  }
  // If HTML5 local storage is available, use it to keep track of
  // events user does not want to see
  if (typeof(Storage) != "undefined") {
        var trfuncs = [];
        function clicktr(i) {
                return function() { hidetr(i, "true"); };
        }
        var elements = document.querySelectorAll('tr.relevant, tr.oldnews');
        for (var i=0; i<elements.length; i++) {
               trfuncs[i] = clicktr(elements[i].id);
               elements[i].addEventListener('click', trfuncs[i]);
               var id = elements[i].id;
               if (sessionStorage.getItem(id) == "hide") { hidetr(id, "false"); }
        }
  }
  // Check for and hide saved hidden maps
  for (var i = 1; i <= 3; i++) {
        var hidemap  = readCookie('map' + i);
        if (hidemap == "hide") { showHide(i); }
  }
  // Check PvP server setting
  var hidepvp = readCookie('pvp');
  if (hidepvp == "hide") {
        showHidePvP();
        document.getElementById('pvptoggle').innerHTML = "(show)";
  }
}
function clearLocalStorage() {
        sessionStorage.clear();
}
function showHide(id) {
        if (document.getElementById('table' + id)) {
                if (document.getElementById('table' + id).style.display != 'none') {
                        document.getElementById('table' + id).style.display = 'none';
                        document.getElementById('label' + id).className = document.getElementById('label' + id).className.replace( /(?:^|\s)downarrow(?!\S)/g, ' rightarrow' );
                        createCookie('map' + id,"hide",365);
                }
                else {
                        document.getElementById('table' + id).style.display = '';
                        document.getElementById('label' + id).className = document.getElementById('label' + id).className.replace( /(?:^|\s)rightarrow(?!\S)/g , ' downarrow' );
                        eraseCookie('map' + id);
                }
        }
}
function showHidePvP() {
        var hidepvp = readCookie('pvp');
        if (hidepvp == "hide") {
                eraseCookie('pvp');
                document.getElementById('pvptoggle').innerHTML = "(hide)";
        }
        else {
                createCookie('pvp','hide',365);
                document.getElementById('pvptoggle').innerHTML = "(show)";
        }
        var elements = document.querySelectorAll('td.pvp1');
        // hidetr takes care of toggling
        for (var i=0; i<elements.length; i++) { hidetr(elements[i].parentNode.id, "false"); }
}
window.onload = initialize;
