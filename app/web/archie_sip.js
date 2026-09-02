/* global JsSIP */
(function (global) {
  var ua = null;
  var session = null;
  var onIncoming = null;
  var onConfirmed = null;
  var onEnded = null;

  function reset() {
    session = null;
    if (typeof onEnded === "function") onEnded();
  }

  global.ArchieSip = {
    start: function (wsUrl, uri, password, displayName, inc, conf, ended) {
      onIncoming = inc;
      onConfirmed = conf;
      onEnded = ended;
      if (typeof JsSIP === "undefined") {
        console.warn("ArchieSip: JsSIP niet geladen");
        return;
      }
      try {
        if (ua) {
          ua.stop();
          ua = null;
        }
        var socket = new JsSIP.WebSocketInterface(wsUrl);
        ua = new JsSIP.UA({
          sockets: [socket],
          uri: uri,
          password: password,
          display_name: displayName || "Paneel",
          register: true,
          session_timers: false
        });
        ua.on("newRTCSession", function (e) {
          session = e.session;
          if (session.direction !== "incoming") return;
          var name = "";
          try {
            name = session.remote_identity.display_name || session.remote_identity.uri.user || "Intercom";
          } catch (_) {
            name = "Intercom";
          }
          if (typeof onIncoming === "function") onIncoming(name);
          session.on("ended", reset);
          session.on("failed", reset);
          session.on("confirmed", function () {
            if (typeof onConfirmed === "function") onConfirmed();
          });
        });
        ua.start();
      } catch (err) {
        console.warn("ArchieSip.start", err);
      }
    },
    stop: function () {
      try {
        if (session) session.terminate();
      } catch (_) {}
      session = null;
      try {
        if (ua) ua.stop();
      } catch (_) {}
      ua = null;
    },
    answer: function () {
      if (!session) return;
      session.answer({
        mediaConstraints: { audio: true, video: false }
      });
    },
    hangup: function () {
      try {
        if (session) session.terminate();
      } catch (_) {}
      session = null;
    },
    mute: function (muted) {
      if (!session) return;
      try {
        if (muted) session.mute({ audio: true, video: false });
        else session.unmute({ audio: true, video: false });
      } catch (_) {}
    }
  };
})(window);
