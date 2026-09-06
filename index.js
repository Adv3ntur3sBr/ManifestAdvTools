document.addEventListener("DOMContentLoaded", () => {
  const currentVersion = "v8.1.0";
  const repoOwner = "l89699756-design";
  const repoName = "ManifestAdvTools";

  // Elements
  const copyBtn = document.getElementById("copyBtn");
  const copyIcon = document.getElementById("copyIcon");
  const copyText = document.getElementById("copyText");
  const installCmd = document.getElementById("installCommand");

  // Adapt install command to current domain if hosted on Vercel or custom domain
  if (installCmd && window.location.protocol.startsWith("http") && !window.location.hostname.includes("localhost") && !window.location.hostname.includes("127.0.0.1")) {
    installCmd.textContent = `irm "${window.location.origin}/install-plugin.ps1" | iex`;
  }

  const checkUpdateBtn = document.getElementById("checkUpdateBtn");
  const updateSpinner = document.getElementById("updateSpinner");
  const latestVerDisplay = document.getElementById("latestVerDisplay");
  const statusBadge = document.getElementById("statusBadge");
  const changelogCard = document.getElementById("changelogCard");
  const changelogBody = document.getElementById("changelogBody");
  const releaseDownloadLink = document.getElementById("releaseDownloadLink");
  const manualDownloadBtn = document.getElementById("manualDownloadBtn");

  // Copy command to clipboard
  if (copyBtn && installCmd) {
    copyBtn.addEventListener("click", () => {
      const textToCopy = installCmd.textContent.trim();
      navigator.clipboard.writeText(textToCopy).then(() => {
        copyBtn.classList.add("copied");
        copyIcon.className = "fa-solid fa-check";
        copyText.textContent = "Copiado!";
        setTimeout(() => {
          copyBtn.classList.remove("copied");
          copyIcon.className = "fa-regular fa-clone";
          copyText.textContent = "Copiar";
        }, 2500);
      }).catch(err => {
        console.error("Falha ao copiar:", err);
      });
    });
  }

  // Check updates via GitHub API
  async function checkUpdates() {
    if (updateSpinner) updateSpinner.classList.add("fa-spin");
    if (latestVerDisplay) latestVerDisplay.textContent = "Buscando...";
    if (statusBadge) {
      statusBadge.className = "status-badge";
      statusBadge.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Verificando no GitHub...';
    }

    const apiUrl = `https://api.github.com/repos/${repoOwner}/${repoName}/releases/latest`;

    try {
      const resp = await fetch(apiUrl, {
        headers: {
          "Accept": "application/vnd.github.v3+json"
        }
      });

      if (resp.status === 404) {
        // No releases published yet
        if (latestVerDisplay) latestVerDisplay.textContent = currentVersion;
        if (statusBadge) {
          statusBadge.className = "status-badge up-to-date";
          statusBadge.innerHTML = '<i class="fa-solid fa-circle-check"></i> Versão mais recente (v8.1.0)';
        }
        if (changelogCard) {
          changelogCard.style.display = "block";
          changelogBody.textContent = "Repositório configurado. O ManifestAdvTools v8.1.0 é a versão mais recente.";
          releaseDownloadLink.href = `https://github.com/${repoOwner}/${repoName}`;
          releaseDownloadLink.innerHTML = '<i class="fa-brands fa-github"></i> Ver Repositório no GitHub';
        }
        return;
      }

      if (!resp.ok) {
        throw new Error(`Erro HTTP: ${resp.status}`);
      }

      const release = await resp.json();
      const latestTag = release.tag_name || release.name || currentVersion;
      if (latestVerDisplay) latestVerDisplay.textContent = latestTag;

      // Find zip asset
      let zipUrl = release.html_url;
      if (release.assets && release.assets.length > 0) {
        const zipAsset = release.assets.find(a => a.name.toLowerCase().endsWith(".zip"));
        if (zipAsset) zipUrl = zipAsset.browser_download_url;
      }

      // Check version comparison
      const isNewer = compareVersions(latestTag, currentVersion) > 0;

      if (statusBadge) {
        if (isNewer) {
          statusBadge.className = "status-badge update-avail";
          statusBadge.innerHTML = `<i class="fa-solid fa-arrow-up"></i> Atualização Disponível (${latestTag})`;
        } else {
          statusBadge.className = "status-badge up-to-date";
          statusBadge.innerHTML = '<i class="fa-solid fa-circle-check"></i> Você está na versão mais recente';
        }
      }

      if (changelogCard) {
        changelogCard.style.display = "block";
        changelogBody.textContent = release.body || "Nenhuma nota de atualização fornecida para este release.";
        releaseDownloadLink.href = zipUrl;
        releaseDownloadLink.innerHTML = `<i class="fa-solid fa-download"></i> Baixar ${latestTag} (.ZIP)`;
      }

    } catch (err) {
      console.error("Erro ao verificar atualizações:", err);
      if (latestVerDisplay) latestVerDisplay.textContent = "Indisponível";
      if (statusBadge) {
        statusBadge.className = "status-badge";
        statusBadge.innerHTML = '<i class="fa-solid fa-triangle-exclamation"></i> Falha ao consultar o GitHub';
      }
    } finally {
      if (updateSpinner) updateSpinner.classList.remove("fa-spin");
    }
  }

  // Version comparator helper (e.g. v8.1.0 vs v8.2.0)
  function compareVersions(v1, v2) {
    const clean = v => v.replace(/^v/, "").split(".").map(Number);
    const p1 = clean(v1);
    const p2 = clean(v2);
    const len = Math.max(p1.length, p2.length);
    for (let i = 0; i < len; i++) {
      const num1 = p1[i] || 0;
      const num2 = p2[i] || 0;
      if (num1 > num2) return 1;
      if (num1 < num2) return -1;
    }
    return 0;
  }

  if (checkUpdateBtn) {
    checkUpdateBtn.addEventListener("click", checkUpdates);
  }

  if (manualDownloadBtn) {
    manualDownloadBtn.addEventListener("click", () => {
      window.open(`https://github.com/${repoOwner}/${repoName}/releases/latest`, "_blank");
    });
  }

  // Initial check on page load
  checkUpdates();
});
