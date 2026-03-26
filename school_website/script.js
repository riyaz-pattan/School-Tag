/* =========================================
   School Tag — script.js
   Particles, scroll reveals, counters, Firebase
   ========================================= */

// ── Firebase Config ──
const firebaseConfig = {
  apiKey: "AIzaSyBKiY7ts6l25ZQ0XcfVYOtsRcGY4-gL5X4",
  authDomain: "student-app-c362d.firebaseapp.com",
  projectId: "student-app-c362d",
  storageBucket: "student-app-c362d.firebasestorage.app",
  messagingSenderId: "807443287145",
  appId: "1:807443287145:web:00e1545145fecefeb766f8",
};
firebase.initializeApp(firebaseConfig);
const db = firebase.firestore();

// ══════════════════════════════════
// PARTICLE ANIMATION
// ══════════════════════════════════
(function initParticles() {
  const canvas = document.getElementById("particles-canvas");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  let particles = [];
  const PARTICLE_COUNT = 60;
  const CONNECT_DIST = 140;
  let mouseX = -1000, mouseY = -1000;
  let w, h;

  function resize() {
    w = canvas.width = canvas.parentElement.clientWidth;
    h = canvas.height = canvas.parentElement.clientHeight;
  }
  resize();
  window.addEventListener("resize", resize);

  canvas.parentElement.addEventListener("mousemove", (e) => {
    const rect = canvas.getBoundingClientRect();
    mouseX = e.clientX - rect.left;
    mouseY = e.clientY - rect.top;
  });
  canvas.parentElement.addEventListener("mouseleave", () => {
    mouseX = -1000;
    mouseY = -1000;
  });

  for (let i = 0; i < PARTICLE_COUNT; i++) {
    particles.push({
      x: Math.random() * w,
      y: Math.random() * h,
      vx: (Math.random() - 0.5) * 0.5,
      vy: (Math.random() - 0.5) * 0.5,
      r: Math.random() * 2 + 1,
      opacity: Math.random() * 0.5 + 0.2,
    });
  }

  function animate() {
    ctx.clearRect(0, 0, w, h);
    for (let i = 0; i < particles.length; i++) {
      const p = particles[i];
      p.x += p.vx;
      p.y += p.vy;
      if (p.x < 0 || p.x > w) p.vx *= -1;
      if (p.y < 0 || p.y > h) p.vy *= -1;

      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(108,99,255,${p.opacity})`;
      ctx.fill();

      // Connect nearby particles
      for (let j = i + 1; j < particles.length; j++) {
        const p2 = particles[j];
        const dx = p.x - p2.x;
        const dy = p.y - p2.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < CONNECT_DIST) {
          ctx.beginPath();
          ctx.moveTo(p.x, p.y);
          ctx.lineTo(p2.x, p2.y);
          ctx.strokeStyle = `rgba(108,99,255,${0.12 * (1 - dist / CONNECT_DIST)})`;
          ctx.lineWidth = 0.6;
          ctx.stroke();
        }
      }

      // Mouse interaction
      const mDx = p.x - mouseX;
      const mDy = p.y - mouseY;
      const mDist = Math.sqrt(mDx * mDx + mDy * mDy);
      if (mDist < 160) {
        ctx.beginPath();
        ctx.moveTo(p.x, p.y);
        ctx.lineTo(mouseX, mouseY);
        ctx.strokeStyle = `rgba(0,212,255,${0.2 * (1 - mDist / 160)})`;
        ctx.lineWidth = 0.8;
        ctx.stroke();
      }
    }
    requestAnimationFrame(animate);
  }
  animate();
})();

// ══════════════════════════════════
// NAVBAR SCROLL EFFECT
// ══════════════════════════════════
const navbar = document.getElementById("navbar");
window.addEventListener("scroll", () => {
  navbar.classList.toggle("scrolled", window.scrollY > 40);
});

// ══════════════════════════════════
// MOBILE MENU TOGGLE
// ══════════════════════════════════
const mobileToggle = document.getElementById("mobile-toggle");
const navLinks = document.getElementById("nav-links");
mobileToggle.addEventListener("click", () => {
  navLinks.classList.toggle("active");
});
// Close on link click
navLinks.querySelectorAll("a").forEach((link) => {
  link.addEventListener("click", () => navLinks.classList.remove("active"));
});

// ══════════════════════════════════
// SCROLL REVEAL (IntersectionObserver)
// ══════════════════════════════════
const revealEls = document.querySelectorAll(".reveal, .reveal-left, .reveal-right");
const revealObserver = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("active");
      }
    });
  },
  { threshold: 0.12, rootMargin: "0px 0px -40px 0px" }
);
revealEls.forEach((el) => revealObserver.observe(el));

// ══════════════════════════════════
// ANIMATED COUNTERS
// ══════════════════════════════════
const counters = document.querySelectorAll(".stat-number[data-target]");
let countersDone = false;

function animateCounters() {
  if (countersDone) return;
  counters.forEach((counter) => {
    const target = +counter.dataset.target;
    const duration = 2000;
    const start = performance.now();

    function update(now) {
      const elapsed = now - start;
      const progress = Math.min(elapsed / duration, 1);
      // ease-out quart
      const ease = 1 - Math.pow(1 - progress, 4);
      const current = Math.floor(ease * target);
      counter.textContent = current.toLocaleString() + (target === 99 ? "%" : "+");
      if (progress < 1) requestAnimationFrame(update);
    }
    requestAnimationFrame(update);
  });
  countersDone = true;
}

const statsSection = document.getElementById("stats");
const statsObserver = new IntersectionObserver(
  (entries) => {
    if (entries[0].isIntersecting) animateCounters();
  },
  { threshold: 0.3 }
);
if (statsSection) statsObserver.observe(statsSection);

// ══════════════════════════════════
// SET MIN DATE FOR DATE PICKER
// ══════════════════════════════════
const dateInput = document.getElementById("demo-date");
if (dateInput) {
  const today = new Date();
  // Set min to tomorrow
  today.setDate(today.getDate() + 1);
  dateInput.min = today.toISOString().split("T")[0];
}

// ══════════════════════════════════
// DEMO BOOKING FORM → FIREBASE
// ══════════════════════════════════
const demoForm = document.getElementById("demo-form");
const btnSubmit = document.getElementById("btn-submit");
const formError = document.getElementById("form-error");
const formSuccess = document.getElementById("form-success");

if (demoForm) {
  demoForm.addEventListener("submit", async (e) => {
    e.preventDefault();
    formError.classList.remove("show");

    const email = document.getElementById("demo-email").value.trim();
    const date = document.getElementById("demo-date").value;
    const time = document.getElementById("demo-time").value;

    // Validate
    if (!email || !date || !time) {
      showError("Please fill in all fields.");
      return;
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      showError("Please enter a valid email address.");
      return;
    }

    // Disable button
    btnSubmit.disabled = true;
    btnSubmit.innerHTML =
      '<span class="material-icons-round" style="font-size:20px;vertical-align:middle;margin-right:6px;animation:spin 1s linear infinite">autorenew</span> Booking...';

    try {
      await db.collection("demo_bookings").add({
        email: email,
        date: date,
        time: time,
        status: "pending",
        created_at: firebase.firestore.FieldValue.serverTimestamp(),
      });

      // Show success
      demoForm.style.display = "none";
      formSuccess.classList.add("show");
    } catch (err) {
      console.error("Error booking demo:", err);
      showError("Something went wrong. Please try again later.");
      btnSubmit.disabled = false;
      btnSubmit.innerHTML =
        '<span class="material-icons-round" style="font-size:20px;vertical-align:middle;margin-right:6px">send</span> Book My Demo';
    }
  });
}

function showError(msg) {
  formError.textContent = msg;
  formError.classList.add("show");
}

// ══════════════════════════════════
// SMOOTH SCROLL FOR ANCHOR LINKS
// ══════════════════════════════════
document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
  anchor.addEventListener("click", (e) => {
    e.preventDefault();
    const target = document.querySelector(anchor.getAttribute("href"));
    if (target) {
      target.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  });
});
