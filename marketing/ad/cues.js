// One timeline for the ad's picture and sound, so every cue lands on the music.
// 120 BPM in 4/4: one beat is 0.5 s, one bar is 2 s. Times are in seconds.
// Every product moment shows something Nudge really does.
(function (root) {
  const BPM = 120;
  const BEAT = 60 / BPM;
  const T = {
    duration: 19.0,

    // 1 · Hook
    hookIn: 0.05, peek: 0.95, notice: 1.25, launch: 1.55,

    // 2 · ⌃⇧Space in System Settings: Nudge looks, then gives the overview
    keys: 2.0, loading: 2.3, overview: 3.2,

    // 3 · The tour: one control at a time, Space for the next
    step1: 4.0, click1: 4.7, space1: 5.25, step2: 5.3, space2: 6.05, step3: 6.1,

    // 4 · Similar controls grouped: a keypad's number keys as one stop
    calc: 7.0,

    // 5 · In a browser, a choice; then a link and where it goes
    safariKeys: 8.4, choice: 8.65, clickWeb: 9.2, webStep: 9.55,

    // 6 · ⌃⇧A: drag a box, and just that part is explained
    areaKeys: 10.8, areaDim: 10.95, dragStart: 11.2, dragEnd: 11.75, clickExplain: 12.0, areaLoading: 12.05, areaCard: 12.6,

    // 7 · Family payoff
    pause: 14.5, lessType: 14.72, found: 15.8,

    // 8–9 · Hero and call to action
    hero: 16.4, wordmark: 16.55, tagline: 16.78, cta: 17.3, pointCTA: 17.52, targetCTA: 17.62, resolve: 18.0, wink: 18.2,
  };
  const cues = { BPM, BEAT, T };
  root.NUDGE_CUES = cues;
  if (typeof module !== 'undefined' && module.exports) module.exports = cues;
})(typeof window !== 'undefined' ? window : globalThis);
