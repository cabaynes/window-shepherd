// The section dots down the right edge: marks the section you're reading.
const links = [...document.querySelectorAll('nav.dots a')];
const sections = links.map(a => document.querySelector(a.getAttribute('href')));
let queued = false;

function mark() {
  queued = false;
  // The current section is the last one whose top has passed 40% of the way down the screen.
  const line = innerHeight * .4;
  let current = 0;
  sections.forEach((s, i) => { if (s && s.getBoundingClientRect().top <= line) current = i; });
  // At the very bottom, the last section is current even if it's short.
  if (innerHeight + scrollY >= document.documentElement.scrollHeight - 2) current = sections.length - 1;
  links.forEach((a, i) => a.setAttribute('aria-current', String(i === current)));
}

addEventListener('scroll', () => { if (!queued) { queued = true; requestAnimationFrame(mark); } }, { passive: true });
addEventListener('resize', mark);
mark();
