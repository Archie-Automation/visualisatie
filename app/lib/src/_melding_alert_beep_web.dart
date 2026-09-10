// Web: repeating two-tone alarm via Web Audio API.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;

/// One urgent two-tone burst (hi-lo).
void playMeldingAlertBeep() {
  _play(r'''
(function(){
  try{
    var C=window.AudioContext||window.webkitAudioContext;
    var c=new C();
    var now=c.currentTime;
    function b(t,f,d){
      var o=c.createOscillator(),g=c.createGain();
      o.connect(g);g.connect(c.destination);
      o.type='square';o.frequency.value=f;
      g.gain.setValueAtTime(0.22,t);
      g.gain.exponentialRampToValueAtTime(0.001,t+d);
      o.start(t);o.stop(t+d+0.02);
    }
    b(now,880,0.16);
    b(now+0.22,1175,0.16);
  }catch(e){}
})()''');
}

void _play(String js_) {
  try {
    js.context.callMethod('eval', [js_]);
  } catch (_) {}
}
