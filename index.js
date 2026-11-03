document.addEventListener("DOMContentLoaded", () => {
  // Single source of truth: <body data-version / data-repo>
  const currentVersion = "v" + (document.body.dataset.version || "0.0.0").replace(/^v/, "");
  const repo = document.body.dataset.repo || "l89699756-design/ManifestAdvTools";
  const repoUrl = `https://github.com/${repo}`;
  const CACHE_KEY = "mat:latest-release";
  const CACHE_TTL = 10 * 60 * 1000; // 10 min — avoids GitHub's 60 req/h anonymous limit

  const $ = id => document.getElementById(id);

  document.querySelectorAll("[data-version-label]").forEach(el => (el.textContent = currentVersion));
  const yearEl = $("year");
  if (yearEl) yearEl.textContent = new Date().getFullYear();

  // Toast
  const toast = $("toast");
  let toastTimer;
  function showToast(msg) {
    if (!toast) return;
    toast.textContent = msg;
    toast.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.remove("show"), 2500);
  }

  // Mobile nav
  const navToggle = $("navToggle");
  const navLinks = $("navLinks");
  if (navToggle && navLinks) {
    const setOpen = open => {
      navLinks.classList.toggle("open", open);
      navToggle.setAttribute("aria-expanded", String(open));
      navToggle.innerHTML = open ? '<i class="fa-solid fa-xmark"></i>' : '<i class="fa-solid fa-bars"></i>';
    };
    navToggle.addEventListener("click", () => setOpen(!navLinks.classList.contains("open")));
    navLinks.addEventListener("click", e => { if (e.target.closest("a")) setOpen(false); });
    document.addEventListener("keydown", e => { if (e.key === "Escape") setOpen(false); });
  }

  // Navbar shadow on scroll
  const navbar = $("navbar");
  const onScroll = () => navbar && navbar.classList.toggle("scrolled", window.scrollY > 10);
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  // Adapt install command to current domain if hosted on Vercel or custom domain
  const installCmdText = $("installCommandText");
  const host = window.location.hostname;
  if (installCmdText && window.location.protocol.startsWith("http") && host && !["localhost", "127.0.0.1"].includes(host)) {
    installCmdText.textContent = `irm "${window.location.origin}/install-plugin.ps1" | iex`;
  }

  // Copy command to clipboard (with fallback for non-secure contexts / file://)
  const copyBtn = $("copyBtn");
  const copyIcon = $("copyIcon");
  const copyText = $("copyText");

  function fallbackCopy(text) {
    const ta = document.createElement("textarea");
    ta.value = text;
    ta.setAttribute("readonly", "");
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    let ok = false;
    try { ok = document.execCommand("copy"); } catch (_) { ok = false; }
    ta.remove();
    return ok ? Promise.resolve() : Promise.reject(new Error("execCommand falhou"));
  }

  if (copyBtn && installCmdText) {
    copyBtn.addEventListener("click", () => {
      const textToCopy = installCmdText.textContent.trim();
      const copy = navigator.clipboard && window.isSecureContext
        ? navigator.clipboard.writeText(textToCopy).catch(() => fallbackCopy(textToCopy))
        : fallbackCopy(textToCopy);

      copy.then(() => {
        copyBtn.classList.add("copied");
        copyIcon.className = "fa-solid fa-check";
        copyText.textContent = "Copiado!";
        showToast("Comando copiado! Cole no PowerShell e pressione Enter.");
        setTimeout(() => {
          copyBtn.classList.remove("copied");
          copyIcon.className = "fa-regular fa-clone";
          copyText.textContent = "Copiar";
        }, 2500);
      }).catch(err => {
        console.error("Falha ao copiar:", err);
        showToast("Não foi possível copiar. Selecione o comando manualmente.");
      });
    });
  }

  // Update checker
  const checkUpdateBtn = $("checkUpdateBtn");
  const updateSpinner = $("updateSpinner");
  const latestVerDisplay = $("latestVerDisplay");
  const statusBadge = $("statusBadge");
  const changelogCard = $("changelogCard");
  const changelogBody = $("changelogBody");
  const changelogDate = $("changelogDate");
  const releaseDownloadLink = $("releaseDownloadLink");
  const manualDownloadBtn = $("manualDownloadBtn");

  function setStatus(kind, icon, text) {
    if (!statusBadge) return;
    statusBadge.className = "status-badge" + (kind ? " " + kind : "");
    statusBadge.innerHTML = `<i class="${icon}"></i> `;
    statusBadge.appendChild(document.createTextNode(text));
  }

  function readCache() {
    try {
      const raw = sessionStorage.getItem(CACHE_KEY);
      if (!raw) return null;
      const { t, data } = JSON.parse(raw);
      return Date.now() - t < CACHE_TTL ? data : null;
    } catch (_) { return null; }
  }

  function writeCache(data) {
    try { sessionStorage.setItem(CACHE_KEY, JSON.stringify({ t: Date.now(), data })); } catch (_) {}
  }

  async function fetchLatestRelease(force) {
    if (!force) {
      const cached = readCache();
      if (cached) return cached;
    }
    const resp = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, {
      headers: { "Accept": "application/vnd.github+json" }
    });
    if (resp.status === 404) {
      const data = { none: true };
      writeCache(data);
      return data;
    }
    if (resp.status === 403 || resp.status === 429) throw new Error("rate-limit");
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);

    const r = await resp.json();
    const zipAsset = (r.assets || []).find(a => a.name.toLowerCase().endsWith(".zip"));
    const data = {
      tag: r.tag_name || r.name || currentVersion,
      body: r.body || "",
      date: r.published_at || null,
      htmlUrl: r.html_url,
      zipUrl: zipAsset ? zipAsset.browser_download_url : null
    };
    writeCache(data);
    return data;
  }

  function renderRelease(rel) {
    changelogCard.hidden = false;

    if (rel.none) {
      latestVerDisplay.textContent = currentVersion;
      setStatus("up-to-date", "fa-solid fa-circle-check", `Versão mais recente (${currentVersion})`);
      changelogDate.textContent = "";
      changelogBody.textContent = `Nenhuma release publicada ainda. O ManifestAdvTools ${currentVersion} é a versão atual.`;
      releaseDownloadLink.href = repoUrl;
      releaseDownloadLink.innerHTML = '<i class="fa-brands fa-github"></i> Ver Repositório no GitHub';
      return;
    }

    latestVerDisplay.textContent = rel.tag;
    if (compareVersions(rel.tag, currentVersion) > 0) {
      setStatus("update-avail", "fa-solid fa-arrow-up", `Atualização disponível (${rel.tag})`);
    } else {
      setStatus("up-to-date", "fa-solid fa-circle-check", "Você está na versão mais recente");
    }

    changelogDate.textContent = rel.date
      ? new Date(rel.date).toLocaleDateString("pt-BR", { day: "2-digit", month: "short", year: "numeric" })
      : "";
    changelogBody.textContent = cleanMarkdown(rel.body) || "Nenhuma nota de atualização fornecida para este release.";
    releaseDownloadLink.href = rel.zipUrl || rel.htmlUrl || repoUrl;
    releaseDownloadLink.innerHTML = `<i class="fa-solid fa-download"></i> Baixar ${escapeHtml(rel.tag)}${rel.zipUrl ? " (.ZIP)" : ""}`;
    if (rel.zipUrl && manualDownloadBtn) manualDownloadBtn.href = rel.zipUrl;
  }

  let checking = false;
  async function checkUpdates(force = false) {
    if (checking) return;
    checking = true;
    if (checkUpdateBtn) checkUpdateBtn.disabled = true;
    if (updateSpinner) updateSpinner.classList.add("fa-spin");
    if (latestVerDisplay) latestVerDisplay.textContent = "Buscando...";
    setStatus("", "fa-solid fa-spinner fa-spin", "Verificando no GitHub...");

    try {
      renderRelease(await fetchLatestRelease(force));
    } catch (err) {
      console.error("Erro ao verificar atualizações:", err);
      if (latestVerDisplay) latestVerDisplay.textContent = "Indisponível";
      setStatus("error", "fa-solid fa-triangle-exclamation",
        err.message === "rate-limit"
          ? "Limite da API do GitHub atingido. Tente novamente em alguns minutos."
          : "Falha ao consultar o GitHub");
    } finally {
      if (updateSpinner) updateSpinner.classList.remove("fa-spin");
      if (checkUpdateBtn) checkUpdateBtn.disabled = false;
      checking = false;
    }
  }

  // Version comparator (handles v8.1.0, 8.2, v8.2.0-beta, etc.)
  function compareVersions(v1, v2) {
    const clean = v => String(v).replace(/^[^\d]*/, "").split(/[.\-+]/).map(n => parseInt(n, 10) || 0);
    const p1 = clean(v1);
    const p2 = clean(v2);
    for (let i = 0; i < Math.max(p1.length, p2.length); i++) {
      const a = p1[i] || 0;
      const b = p2[i] || 0;
      if (a !== b) return a > b ? 1 : -1;
    }
    return 0;
  }

  // Strip the noisiest markdown so release notes read well as plain text
  function cleanMarkdown(md) {
    return String(md)
      .replace(/\r\n/g, "\n")
      .replace(/^#{1,6}\s*/gm, "")
      .replace(/\*\*(.+?)\*\*/g, "$1")
      .replace(/`([^`]+)`/g, "$1")
      .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
      .replace(/^\s*[-*]\s+/gm, "• ")
      .replace(/\n{3,}/g, "\n\n")
      .trim();
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  }

  if (checkUpdateBtn) checkUpdateBtn.addEventListener("click", () => checkUpdates(true));

  // Reveal-on-scroll
  const revealEls = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    const io = new IntersectionObserver(entries => {
      entries.forEach(e => {
        if (e.isIntersecting) {
          e.target.classList.add("visible");
          io.unobserve(e.target);
        }
      });
    }, { threshold: 0.12 });
    revealEls.forEach(el => io.observe(el));
  } else {
    revealEls.forEach(el => el.classList.add("visible"));
  }

  // Initial check on page load (served from cache when fresh)
  checkUpdates();
});
