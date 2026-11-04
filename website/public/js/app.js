document.addEventListener('DOMContentLoaded', () => {
  // 1. Unique Visitor Identification & Tracking
  const VISITOR_KEY = 'frames_unique_visitor_id';
  let visitorId = localStorage.getItem(VISITOR_KEY);
  if (!visitorId) {
    visitorId = typeof crypto.randomUUID === 'function' ? crypto.randomUUID() : 'vis_' + Math.random().toString(36).substring(2, 15);
    localStorage.setItem(VISITOR_KEY, visitorId);
  }

  // Live stat counter elements
  const elUniqueVisitors = document.getElementById('stat-unique-visitors');
  const elTotalDownloads = document.getElementById('stat-total-downloads');
  const elUniqueDownloads = document.getElementById('stat-unique-downloads');
  const elTotalViews = document.getElementById('stat-total-views');

  function animateCount(el, targetValue) {
    if (!el) return;
    const startValue = parseInt(el.textContent.replace(/,/g, ''), 10) || 0;
    if (startValue === targetValue) return;

    const duration = 1000;
    const startTime = performance.now();

    function step(currentTime) {
      const elapsed = currentTime - startTime;
      const progress = Math.min(elapsed / duration, 1.0);
      // ease-out cubic
      const eased = 1 - Math.pow(1 - progress, 3);
      const current = Math.floor(startValue + (targetValue - startValue) * eased);
      el.textContent = current.toLocaleString();

      if (progress < 1.0) {
        requestAnimationFrame(step);
      } else {
        el.textContent = targetValue.toLocaleString();
      }
    }
    requestAnimationFrame(step);
  }

  function updateStatsUI(stats) {
    if (stats.uniqueVisitors !== undefined) animateCount(elUniqueVisitors, stats.uniqueVisitors);
    if (stats.totalDownloads !== undefined) animateCount(elTotalDownloads, stats.totalDownloads);
    if (stats.uniqueDownloads !== undefined) animateCount(elUniqueDownloads, stats.uniqueDownloads);
    if (stats.totalPageViews !== undefined) animateCount(elTotalViews, stats.totalPageViews);
  }

  // Register visit
  fetch('/api/track-visit', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Visitor-Id': visitorId
    },
    body: JSON.stringify({ visitorId })
  })
    .then(res => res.json())
    .then(data => {
      if (data && data.success) {
        updateStatsUI(data);
      }
    })
    .catch(err => console.error('Track visit error:', err));

  // 2. Download Buttons Handler
  const downloadButtons = document.querySelectorAll('.trigger-download');
  downloadButtons.forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();

      // Send download beacon
      fetch('/api/track-download', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Visitor-Id': visitorId
        },
        body: JSON.stringify({ visitorId })
      })
        .then(res => res.json())
        .then(data => {
          if (data && data.success) {
            updateStatsUI(data);
          }
        })
        .catch(err => console.error('Track download error:', err));

      // Trigger actual download stream
      window.location.href = '/download';
    });
  });

  // 3. Scroll Reveal via IntersectionObserver (per B7)
  const revealElements = document.querySelectorAll('.reveal-on-scroll');
  if ('IntersectionObserver' in window) {
    const revealObserver = new IntersectionObserver((entries, observer) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('revealed');
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.15 });

    revealElements.forEach(el => revealObserver.observe(el));
  } else {
    revealElements.forEach(el => el.classList.add('revealed'));
  }

  // 4. Tagline Reveal Section (Mandatory per B11)
  // Words transition individually from 28% opacity to full color in reading order
  const taglineEl = document.querySelector('.tagline-text');
  if (taglineEl) {
    const rawWords = taglineEl.textContent.trim().split(/\s+/);
    taglineEl.innerHTML = '';
    const wordSpans = rawWords.map(word => {
      const span = document.createElement('span');
      span.className = 'tagline-word';
      span.textContent = word + ' ';
      taglineEl.appendChild(span);
      return span;
    });

    if ('IntersectionObserver' in window) {
      const taglineObserver = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            wordSpans.forEach((span, index) => {
              setTimeout(() => {
                span.classList.add('active');
              }, index * 45); // Staggered activation
            });
          }
        });
      }, { threshold: 0.3 });

      taglineObserver.observe(taglineEl);
    }
  }

  // 5. 4K Screenshots & Media Gallery Tab Switching
  const galleryTabs = document.querySelectorAll('.gallery-tab-btn');
  const gallerySlides = document.querySelectorAll('.gallery-slide');

  galleryTabs.forEach(tab => {
    tab.addEventListener('click', () => {
      const targetId = tab.getAttribute('data-target');

      galleryTabs.forEach(t => t.classList.remove('active'));
      gallerySlides.forEach(s => s.classList.remove('active'));

      tab.classList.add('active');
      const targetSlide = document.getElementById(targetId);
      if (targetSlide) {
        targetSlide.classList.add('active');
      }
    });
  });

  // 6. FAQ Accordion
  const faqItems = document.querySelectorAll('.faq-item');
  faqItems.forEach(item => {
    const trigger = item.querySelector('.faq-trigger');
    if (trigger) {
      trigger.addEventListener('click', () => {
        const isOpen = item.classList.contains('open');
        faqItems.forEach(i => i.classList.remove('open'));
        if (!isOpen) {
          item.classList.add('open');
        }
      });
    }
  });

  // 7. Interactive Feedback Form
  const feedbackForm = document.getElementById('feedback-form');
  const feedbackStatus = document.getElementById('feedback-status');

  if (feedbackForm) {
    feedbackForm.addEventListener('submit', (e) => {
      e.preventDefault();

      const name = document.getElementById('feedback-name').value.trim();
      const email = document.getElementById('feedback-email').value.trim();
      const type = document.getElementById('feedback-type').value;
      const message = document.getElementById('feedback-message').value.trim();

      if (!message) {
        if (feedbackStatus) {
          feedbackStatus.textContent = 'Please enter a message.';
          feedbackStatus.style.color = '#ef4444';
        }
        return;
      }

      if (feedbackStatus) {
        feedbackStatus.textContent = 'Submitting feedback...';
        feedbackStatus.style.color = '#9B9B9B';
      }

      fetch('/api/feedback', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, email, type, message })
      })
        .then(res => res.json())
        .then(data => {
          if (data && data.success) {
            feedbackForm.reset();
            if (feedbackStatus) {
              feedbackStatus.textContent = 'Feedback received. Thank you for helping improve Frames!';
              feedbackStatus.style.color = '#22c55e';
            }
          } else {
            throw new Error(data.error || 'Submission failed');
          }
        })
        .catch(err => {
          if (feedbackStatus) {
            feedbackStatus.textContent = 'Direct submission failed. You can email theavidwivedi@gmail.com directly.';
            feedbackStatus.style.color = '#ef4444';
          }
        });
    });
  }
});
