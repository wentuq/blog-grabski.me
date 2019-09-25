document.addEventListener("DOMContentLoaded", theDomHasLoaded, false);
window.addEventListener("load", pageFullyLoaded, false);

function theDomHasLoaded(e) {
    lightGallery(document.getElementById('lightgallery'));
}

function pageFullyLoaded(e) {
    // do something again
}