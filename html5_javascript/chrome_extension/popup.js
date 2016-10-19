// Copyright (c) 2014 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

document.addEventListener('DOMContentLoaded', function() {
  // only enters here after they click on the icon
  // no access *at all* to the current tab DOM apparently :|

   var h=document.getElementById("edited_requested");
   h.addEventListener("click", loadEditedPlayback);
});

function loadEditedPlayback() {
    console.log('popup.js here2');
    chrome.tabs.query({active: true, currentWindow: true}, function(tabs) {
        chrome.tabs.sendMessage(tabs[0].id, {action: 'start', greeting: "hello"}, function(response) {
            console.log(response.farewell);
        });
    });
    console.log('popup.js here3');
}
