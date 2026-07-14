// Web implementation: generates Satel-style piezo beeps via the Web Audio API.
// Uses dart:js eval to avoid dart:html AudioContext availability issues.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;

/// Play a single short piezo-style beep (used for exit-delay: one beep/s).
void beepOnce({double frequency = 900.0, double durationSec = 0.10}) {
  _play('''
(function(){
  try{
    var c=new(window.AudioContext||window.webkitAudioContext)();
    var now=c.currentTime;
    _b(c,now,$frequency,$durationSec);
    function _b(c,t,f,d){
      var o=c.createOscillator(),g=c.createGain();
      o.connect(g);g.connect(c.destination);
      o.type='square';o.frequency.value=f;
      g.gain.setValueAtTime(0.18,t);
      g.gain.exponentialRampToValueAtTime(0.001,t+d);
      o.start(t);o.stop(t+d+0.02);
    }
  }catch(e){}
})()''');
}

/// Play two quick beeps in succession (used for entry-delay: bi-bi pattern).
void beepDouble({double frequency = 1100.0, double durationSec = 0.08}) {
  _play('''
(function(){
  try{
    var c=new(window.AudioContext||window.webkitAudioContext)();
    var now=c.currentTime;
    _b(c,now,$frequency,$durationSec);
    _b(c,now+${durationSec + 0.08},$frequency,$durationSec);
    function _b(c,t,f,d){
      var o=c.createOscillator(),g=c.createGain();
      o.connect(g);g.connect(c.destination);
      o.type='square';o.frequency.value=f;
      g.gain.setValueAtTime(0.18,t);
      g.gain.exponentialRampToValueAtTime(0.001,t+d);
      o.start(t);o.stop(t+d+0.02);
    }
  }catch(e){}
})()''');
}

void _play(String js_) {
  try {
    js.context.callMethod('eval', [js_]);
  } catch (_) {}
}
