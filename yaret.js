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
function dopref() {
  var headers = ["Event", "Shard", "Zone", "Age"]; 
  var funcs = [];
  function createfunc(i) {
    return function() { createCookie("sort",i,365); };
  }
  for (var h=0; h<headers.length; h++) {
    var elements = document.getElementsByClassName(headers[h]);  
    funcs[h] = createfunc(headers[h]);
    for (var i=0; i<elements.length; i++) { 
      elements[i].addEventListener('click', funcs[h]);
    }
  }
  var sortpref = readCookie('sort');
  if (sortpref) {
    var sortname = sortpref + "";
    var elements = document.getElementsByClassName(sortname);
    for (var i=0; i<elements.length; i++) {
      sorttable.innerSortFunction.apply(elements[i], []);
    }
  }
}
window.onload = dopref;
function eraseCookie(name) {
        createCookie(name,"",-1);
}
