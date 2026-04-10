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
// PARTICLE ANIMATION — warm theme
// ══════════════════════════════════
(function initParticles() {
  const canvas = document.getElementById("particles-canvas");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  let particles = [];
  const PARTICLE_COUNT = 50;
  const CONNECT_DIST = 130;
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

  // Warm color palette for particles
  const particleColors = [
    { r: 249, g: 115, b: 22 },   // orange
    { r: 251, g: 191, b: 36 },   // yellow
    { r: 37, g: 99, b: 235 },    // blue
    { r: 139, g: 92, b: 246 },   // purple
  ];

  for (let i = 0; i < PARTICLE_COUNT; i++) {
    const color = particleColors[Math.floor(Math.random() * particleColors.length)];
    particles.push({
      x: Math.random() * w,
      y: Math.random() * h,
      vx: (Math.random() - 0.5) * 0.4,
      vy: (Math.random() - 0.5) * 0.4,
      r: Math.random() * 2.5 + 1,
      opacity: Math.random() * 0.25 + 0.08,
      color: color,
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
      ctx.fillStyle = `rgba(${p.color.r},${p.color.g},${p.color.b},${p.opacity})`;
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
          ctx.strokeStyle = `rgba(249,115,22,${0.06 * (1 - dist / CONNECT_DIST)})`;
          ctx.lineWidth = 0.5;
          ctx.stroke();
        }
      }

      // Mouse interaction
      const mDx = p.x - mouseX;
      const mDy = p.y - mouseY;
      const mDist = Math.sqrt(mDx * mDx + mDy * mDy);
      if (mDist < 150) {
        ctx.beginPath();
        ctx.moveTo(p.x, p.y);
        ctx.lineTo(mouseX, mouseY);
        ctx.strokeStyle = `rgba(251,191,36,${0.15 * (1 - mDist / 150)})`;
        ctx.lineWidth = 0.7;
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
// EMAIL & PHONE VALIDATION HELPERS
// ══════════════════════════════════

/**
 * Validates email format:
 *  - Must contain exactly one '@'
 *  - Must have at least 1 character before '@'
 *  - Must have at least 1 letter between '@' and '.'
 *  - Must have a '.' after '@' with at least 1 letter between '@' and '.'
 *  - Must have at least 2 characters after the last '.'
 */
function isValidEmail(email) {
  // Basic structure check
  if (!email || email.length < 5) return false;

  const atIndex = email.indexOf("@");
  const lastAtIndex = email.lastIndexOf("@");

  // Must have exactly one '@'
  if (atIndex === -1 || atIndex !== lastAtIndex) return false;

  const localPart = email.substring(0, atIndex);
  const domainPart = email.substring(atIndex + 1);

  // Local part must have at least 1 character
  if (localPart.length < 1) return false;

  // Domain must have at least one '.'
  const dotIndex = domainPart.indexOf(".");
  if (dotIndex === -1) return false;

  // Must be at least 1 letter between '@' and '.'
  const beforeDot = domainPart.substring(0, dotIndex);
  if (beforeDot.length < 1 || !/[a-zA-Z]/.test(beforeDot)) return false;

  // Must have at least 2 characters after last '.'
  const lastDotIndex = domainPart.lastIndexOf(".");
  const afterDot = domainPart.substring(lastDotIndex + 1);
  if (afterDot.length < 2 || !/^[a-zA-Z]+$/.test(afterDot)) return false;

  // No spaces allowed
  if (/\s/.test(email)) return false;

  return true;
}

/**
 * Validates Indian mobile number: exactly 10 digits, starts with 6-9
 */
function isValidPhone(phone) {
  const cleaned = phone.replace(/\s/g, "");
  return /^[6-9]\d{9}$/.test(cleaned);
}

// ── Live inline hints ──
const emailInput = document.getElementById("demo-email");
const phoneInput = document.getElementById("demo-phone");
const emailHint = document.getElementById("email-hint");
const phoneHint = document.getElementById("phone-hint");

if (emailInput && emailHint) {
  emailInput.addEventListener("input", () => {
    const val = emailInput.value.trim();
    if (!val) {
      emailHint.textContent = "";
      emailHint.className = "field-hint";
    } else if (isValidEmail(val)) {
      emailHint.textContent = "✓ Valid email";
      emailHint.className = "field-hint success";
    } else {
      // Give specific feedback
      if (!val.includes("@")) {
        emailHint.textContent = "Email must contain '@'";
      } else if (!val.includes(".")) {
        emailHint.textContent = "Email must contain a '.' in the domain";
      } else {
        emailHint.textContent = "Enter a valid email (e.g. name@school.com)";
      }
      emailHint.className = "field-hint error";
    }
  });
}

if (phoneInput && phoneHint) {
  // Only allow digits
  phoneInput.addEventListener("input", () => {
    phoneInput.value = phoneInput.value.replace(/\D/g, "").slice(0, 10);
    const val = phoneInput.value;
    if (!val) {
      phoneHint.textContent = "";
      phoneHint.className = "field-hint";
    } else if (val.length < 10) {
      phoneHint.textContent = `${10 - val.length} more digit${10 - val.length > 1 ? "s" : ""} needed`;
      phoneHint.className = "field-hint error";
    } else if (isValidPhone(val)) {
      phoneHint.textContent = "✓ Valid mobile number";
      phoneHint.className = "field-hint success";
    } else {
      phoneHint.textContent = "Must start with 6, 7, 8, or 9";
      phoneHint.className = "field-hint error";
    }
  });
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
    const phone = document.getElementById("demo-phone").value.trim();
    const date = document.getElementById("demo-date").value;
    const time = document.getElementById("demo-time").value;

    // Validate all fields filled
    if (!email || !phone || !date || !time) {
      showError("Please fill in all fields.");
      return;
    }

    // Email validation
    if (!isValidEmail(email)) {
      if (!email.includes("@")) {
        showError("Email must contain '@' symbol.");
      } else if (!email.includes(".")) {
        showError("Email must contain a '.' in the domain.");
      } else {
        showError("Please enter a valid email address (e.g. name@school.com).");
      }
      return;
    }

    // Phone validation
    if (!isValidPhone(phone)) {
      if (phone.length !== 10) {
        showError("Mobile number must be exactly 10 digits.");
      } else {
        showError("Mobile number must start with 6, 7, 8, or 9.");
      }
      return;
    }

    // Disable button
    btnSubmit.disabled = true;
    btnSubmit.innerHTML =
      '<span class="material-icons-round" style="font-size:20px;vertical-align:middle;margin-right:6px;animation:spin 1s linear infinite">autorenew</span> Booking...';

    try {
      await db.collection("demo_bookings").add({
        email: email,
        phone: "+91" + phone,
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
