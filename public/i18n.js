// Site translations. The Portuguese text in index.html is the key, so a new
// string only needs an entry here; anything missing just stays in Portuguese.
(function () {
  const LANGS = {
    pt: { label: "Português", html: "pt-BR", date: "pt-BR" },
    en: { label: "English", html: "en", date: "en-US" },
    es: { label: "Español", html: "es", date: "es-ES" }
  };

  const DICT = {
    en: {
      // page
      "ManifestAdvTools — Console de Manifestos para Steam": "ManifestAdvTools — Manifest Console for Steam",
      "Pular para o conteúdo": "Skip to content",
      "ManifestAdvTools — início": "ManifestAdvTools — home",
      "Abrir menu": "Open menu",
      "Idioma": "Language",
      "Como funciona": "How it works",
      "Fontes": "Sources",
      "Recursos": "Features",
      "Atualizações": "Updates",
      "Desinstalar": "Uninstall",
      // hero
      "Roda dentro da Steam, via Millennium": "Runs inside Steam, via Millennium",
      "O console que abastece a sua biblioteca da Steam.": "The console that stocks your Steam library.",
      "Digita o AppID, o ManifestAdvTools varre 6 fontes públicas, injeta o manifesto e aplica o OnlineFix. Sem editar arquivo na mão.":
        "Type the AppID and ManifestAdvTools scans 6 public sources, injects the manifest and applies OnlineFix. No hand-editing files.",
      "Windows · PowerShell · instalação em 1 comando": "Windows · PowerShell · 1-command install",
      "Linux / SteamOS (Steam Deck) · Bash · instalação em 1 comando": "Linux / SteamOS (Steam Deck) · Bash · 1-command install",
      "Copiar comando Windows": "Copy Windows command",
      "Copiar comando Linux": "Copy Linux command",
      "Copiar": "Copy",
      "Copiado!": "Copied!",
      "Baixar ZIP": "Download ZIP",
      "Ver como funciona": "See how it works",
      "Instala o Millennium sozinho se faltar. Código aberto.": "Installs Millennium by itself if missing. Open source.",
      "Prévia do painel do plugin": "Plugin panel preview",
      "Varrendo fontes": "Scanning sources",
      "Manifesto injetado": "Manifest injected",
      "Reinicie a Steam": "Restart Steam",
      "fontes com fallback": "sources with fallback",
      "temas da biblioteca": "library themes",
      "idiomas": "languages",
      "comando pra instalar": "command to install",
      // how
      "Como um jogo entra na sua biblioteca": "How a game gets into your library",
      "Cinco etapas. O plugin faz as cinco; você só digita o AppID e reinicia a Steam.":
        "Five steps. The plugin does all five; you just type the AppID and restart Steam.",
      "Você informa o AppID": "You enter the AppID",
      "O número do jogo na Steam. O plugin aceita direto da página da loja.": "The game's number on Steam. The plugin takes it straight from the store page.",
      "Varre as 6 fontes": "Scans the 6 sources",
      "Consulta os provedores em ordem, um por um, até achar o manifesto.": "Queries the providers in order, one by one, until it finds the manifest.",
      "Primeiro acerto vence": "First hit wins",
      "Achou numa fonte, para. Se uma cai, o fallback tenta a próxima sozinho.": "Found in one source, it stops. If one is down, the fallback tries the next on its own.",
      "Injeta o manifesto": "Injects the manifest",
      "Grava o Lua/depot no lugar certo da Steam e, se houver, aplica o OnlineFix.": "Writes the Lua/depot to the right place in Steam and applies OnlineFix if there is one.",
      "Reinicia a Steam": "Restarts Steam",
      "O jogo aparece na biblioteca, pronto pra baixar.": "The game shows up in your library, ready to download.",
      // sources
      "As 6 fontes, com fallback automático": "The 6 sources, with automatic fallback",
      "Se uma fonte sair do ar, o plugin passa pra próxima sem você perceber.": "If a source goes down, the plugin moves to the next one without you noticing.",
      "+ a sua própria fonte": "+ your own source",
      // capabilities
      "O que mais ele faz": "What else it does",
      "OnlineFix integrado": "Built-in OnlineFix",
      "Baixa e extrai patches de multiplayer automaticamente. Dá pra desfazer depois.": "Downloads and extracts multiplayer patches automatically. You can undo them later.",
      "Funciona no controle": "Works with a controller",
      "Navegação adaptada pra gamepad e Big Picture, com atalhos.": "Navigation adapted for gamepad and Big Picture, with shortcuts.",
      "Mais de 30 idiomas": "More than 30 languages",
      "Português, Inglês, Espanhol, Japonês e muitos outros.": "Portuguese, English, Spanish, Japanese and many more.",
      "Atualiza sozinho": "Updates itself",
      "Checa nova versão a cada 2h e se atualiza sem reinstalar.": "Checks for a new version every 2h and updates without reinstalling.",
      "12 temas pra biblioteca": "12 library themes",
      "cores reais do plugin": "the plugin's real colors",
      "Depot (padrão)": "Depot (default)",
      // updates
      "Central de atualizações": "Update center",
      "Consulta a versão mais recente direto do repositório oficial.": "Checks the latest version straight from the official repository.",
      "repositório oficial": "official repository",
      "Verificar": "Check",
      "Versão do site": "Site version",
      "Mais recente": "Latest",
      "Pronto": "Ready",
      "Notas da versão": "Release notes",
      "Baixar release": "Download release",
      // uninstall
      "Quer tirar tudo?": "Want to remove everything?",
      "Um comando remove Millennium, Steamtools, ManifestAdvTools e os scripts Lua. A Steam volta ao original. Seus jogos e sua conta não são tocados.":
        "One command removes Millennium, Steamtools, ManifestAdvTools and the Lua scripts. Steam goes back to stock. Your games and account are not touched.",
      "Windows (PowerShell) · desinstalar e restaurar a Steam": "Windows (PowerShell) · uninstall and restore Steam",
      "Linux / SteamOS (Bash) · desinstalar e restaurar a Steam": "Linux / SteamOS (Bash) · uninstall and restore Steam",
      "Copiar comando de desinstalação Windows": "Copy Windows uninstall command",
      "Copiar comando de desinstalação Linux": "Copy Linux uninstall command",
      // footer
      "· feito pra comunidade gamer": "· made for the gaming community",
      "Voltar ao topo": "Back to top",
      // index.js messages
      "Comando copiado! Cole no terminal Linux e pressione Enter.": "Command copied! Paste it in the Linux terminal and press Enter.",
      "Comando copiado! Cole no PowerShell e pressione Enter.": "Command copied! Paste it in PowerShell and press Enter.",
      "Não foi possível copiar. Selecione o comando manualmente.": "Couldn't copy. Select the command by hand.",
      "Versão mais recente ({v})": "Latest version ({v})",
      "Nenhuma release publicada ainda. O ManifestAdvTools {v} é a versão atual.": "No release published yet. ManifestAdvTools {v} is the current version.",
      "Ver Repositório no GitHub": "View repository on GitHub",
      "Atualização disponível ({v})": "Update available ({v})",
      "Você está na versão mais recente": "You're on the latest version",
      "Nenhuma nota de atualização fornecida para este release.": "No release notes for this release.",
      "Baixar {v}": "Download {v}",
      "Buscando...": "Fetching...",
      "Verificando no GitHub...": "Checking GitHub...",
      "Indisponível": "Unavailable",
      "Limite da API do GitHub atingido. Tente novamente em alguns minutos.": "GitHub API limit reached. Try again in a few minutes.",
      "Falha ao consultar o GitHub": "Couldn't reach GitHub"
    },
    es: {
      "ManifestAdvTools — Console de Manifestos para Steam": "ManifestAdvTools — Consola de manifiestos para Steam",
      "Pular para o conteúdo": "Saltar al contenido",
      "ManifestAdvTools — início": "ManifestAdvTools — inicio",
      "Abrir menu": "Abrir menú",
      "Idioma": "Idioma",
      "Como funciona": "Cómo funciona",
      "Fontes": "Fuentes",
      "Recursos": "Funciones",
      "Atualizações": "Actualizaciones",
      "Desinstalar": "Desinstalar",
      "Roda dentro da Steam, via Millennium": "Funciona dentro de Steam, vía Millennium",
      "O console que abastece a sua biblioteca da Steam.": "La consola que llena tu biblioteca de Steam.",
      "Digita o AppID, o ManifestAdvTools varre 6 fontes públicas, injeta o manifesto e aplica o OnlineFix. Sem editar arquivo na mão.":
        "Escribe el AppID y ManifestAdvTools revisa 6 fuentes públicas, inyecta el manifiesto y aplica OnlineFix. Sin editar archivos a mano.",
      "Windows · PowerShell · instalação em 1 comando": "Windows · PowerShell · instalación en 1 comando",
      "Linux / SteamOS (Steam Deck) · Bash · instalação em 1 comando": "Linux / SteamOS (Steam Deck) · Bash · instalación en 1 comando",
      "Copiar comando Windows": "Copiar comando de Windows",
      "Copiar comando Linux": "Copiar comando de Linux",
      "Copiar": "Copiar",
      "Copiado!": "¡Copiado!",
      "Baixar ZIP": "Descargar ZIP",
      "Ver como funciona": "Ver cómo funciona",
      "Instala o Millennium sozinho se faltar. Código aberto.": "Instala Millennium solo si falta. Código abierto.",
      "Prévia do painel do plugin": "Vista previa del panel del plugin",
      "Varrendo fontes": "Revisando fuentes",
      "/6 online": "/6 en línea",
      "Manifesto injetado": "Manifiesto inyectado",
      "Reinicie a Steam": "Reinicia Steam",
      "fontes com fallback": "fuentes con respaldo",
      "temas da biblioteca": "temas de biblioteca",
      "idiomas": "idiomas",
      "comando pra instalar": "comando para instalar",
      "Como um jogo entra na sua biblioteca": "Cómo entra un juego en tu biblioteca",
      "Cinco etapas. O plugin faz as cinco; você só digita o AppID e reinicia a Steam.":
        "Cinco pasos. El plugin hace los cinco; tú solo escribes el AppID y reinicias Steam.",
      "Você informa o AppID": "Indicas el AppID",
      "O número do jogo na Steam. O plugin aceita direto da página da loja.": "El número del juego en Steam. El plugin lo toma directo de la página de la tienda.",
      "Varre as 6 fontes": "Revisa las 6 fuentes",
      "Consulta os provedores em ordem, um por um, até achar o manifesto.": "Consulta los proveedores en orden, uno por uno, hasta encontrar el manifiesto.",
      "Primeiro acerto vence": "Gana el primer acierto",
      "Achou numa fonte, para. Se uma cai, o fallback tenta a próxima sozinho.": "Si lo encuentra en una fuente, se detiene. Si una falla, el respaldo prueba la siguiente solo.",
      "Injeta o manifesto": "Inyecta el manifiesto",
      "Grava o Lua/depot no lugar certo da Steam e, se houver, aplica o OnlineFix.": "Guarda el Lua/depot en el lugar correcto de Steam y, si existe, aplica OnlineFix.",
      "Reinicia a Steam": "Reinicia Steam",
      "O jogo aparece na biblioteca, pronto pra baixar.": "El juego aparece en la biblioteca, listo para descargar.",
      "As 6 fontes, com fallback automático": "Las 6 fuentes, con respaldo automático",
      "Se uma fonte sair do ar, o plugin passa pra próxima sem você perceber.": "Si una fuente se cae, el plugin pasa a la siguiente sin que lo notes.",
      "+ a sua própria fonte": "+ tu propia fuente",
      "O que mais ele faz": "Qué más hace",
      "OnlineFix integrado": "OnlineFix integrado",
      "Baixa e extrai patches de multiplayer automaticamente. Dá pra desfazer depois.": "Descarga y extrae parches multijugador automáticamente. Se pueden deshacer después.",
      "Funciona no controle": "Funciona con mando",
      "Navegação adaptada pra gamepad e Big Picture, com atalhos.": "Navegación adaptada a mando y Big Picture, con atajos.",
      "Mais de 30 idiomas": "Más de 30 idiomas",
      "Português, Inglês, Espanhol, Japonês e muitos outros.": "Portugués, inglés, español, japonés y muchos más.",
      "Atualiza sozinho": "Se actualiza solo",
      "Checa nova versão a cada 2h e se atualiza sem reinstalar.": "Busca una versión nueva cada 2 h y se actualiza sin reinstalar.",
      "12 temas pra biblioteca": "12 temas para la biblioteca",
      "cores reais do plugin": "colores reales del plugin",
      "Depot (padrão)": "Depot (predeterminado)",
      "Central de atualizações": "Centro de actualizaciones",
      "Consulta a versão mais recente direto do repositório oficial.": "Consulta la versión más reciente directo del repositorio oficial.",
      "repositório oficial": "repositorio oficial",
      "Verificar": "Comprobar",
      "Versão do site": "Versión del sitio",
      "Mais recente": "Más reciente",
      "Status": "Estado",
      "Pronto": "Listo",
      "Notas da versão": "Notas de la versión",
      "Baixar release": "Descargar release",
      "Quer tirar tudo?": "¿Quieres quitarlo todo?",
      "Um comando remove Millennium, Steamtools, ManifestAdvTools e os scripts Lua. A Steam volta ao original. Seus jogos e sua conta não são tocados.":
        "Un comando quita Millennium, Steamtools, ManifestAdvTools y los scripts Lua. Steam vuelve a como era. Tus juegos y tu cuenta no se tocan.",
      "Windows (PowerShell) · desinstalar e restaurar a Steam": "Windows (PowerShell) · desinstalar y restaurar Steam",
      "Linux / SteamOS (Bash) · desinstalar e restaurar a Steam": "Linux / SteamOS (Bash) · desinstalar y restaurar Steam",
      "Copiar comando de desinstalação Windows": "Copiar comando de desinstalación de Windows",
      "Copiar comando de desinstalação Linux": "Copiar comando de desinstalación de Linux",
      "· feito pra comunidade gamer": "· hecho para la comunidad gamer",
      "Voltar ao topo": "Volver arriba",
      "Comando copiado! Cole no terminal Linux e pressione Enter.": "¡Comando copiado! Pégalo en la terminal de Linux y pulsa Enter.",
      "Comando copiado! Cole no PowerShell e pressione Enter.": "¡Comando copiado! Pégalo en PowerShell y pulsa Enter.",
      "Não foi possível copiar. Selecione o comando manualmente.": "No se pudo copiar. Selecciona el comando a mano.",
      "Versão mais recente ({v})": "Versión más reciente ({v})",
      "Nenhuma release publicada ainda. O ManifestAdvTools {v} é a versão atual.": "Aún no hay releases. ManifestAdvTools {v} es la versión actual.",
      "Ver Repositório no GitHub": "Ver repositorio en GitHub",
      "Atualização disponível ({v})": "Actualización disponible ({v})",
      "Você está na versão mais recente": "Tienes la versión más reciente",
      "Nenhuma nota de atualização fornecida para este release.": "Este release no tiene notas.",
      "Baixar {v}": "Descargar {v}",
      "Buscando...": "Buscando...",
      "Verificando no GitHub...": "Comprobando en GitHub...",
      "Indisponível": "No disponible",
      "Limite da API do GitHub atingido. Tente novamente em alguns minutos.": "Límite de la API de GitHub alcanzado. Inténtalo de nuevo en unos minutos.",
      "Falha ao consultar o GitHub": "No se pudo consultar GitHub"
    }
  };

  const STORE_KEY = "mat:lang";

  // Text that index.js writes later is already translated; map it back to the
  // Portuguese key so a later language switch can still translate it
  const REVERSE = {};
  Object.keys(DICT).forEach(code => Object.keys(DICT[code]).forEach(pt => (REVERSE[DICT[code][pt]] = pt)));

  function detect() {
    try {
      const saved = localStorage.getItem(STORE_KEY);
      if (saved && LANGS[saved]) return saved;
    } catch (_) {}
    const nav = (navigator.language || "pt").slice(0, 2).toLowerCase();
    return LANGS[nav] ? nav : "pt";
  }

  let lang = detect();

  // t("Texto em português", { v: "8.5.0" })
  function t(key, vars) {
    const table = DICT[lang];
    let s = (table && table[key]) || key;
    if (vars) Object.keys(vars).forEach(k => (s = s.split("{" + k + "}").join(vars[k])));
    return s;
  }

  // Text nodes and attributes remember their Portuguese original, so switching
  // back and forth always translates from the source text
  const originals = new WeakMap();
  const SKIP = "script, style, code, [data-no-i18n]";

  function translateDom() {
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
      acceptNode: n => (n.parentElement && n.parentElement.closest(SKIP) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT)
    });
    let node;
    while ((node = walker.nextNode())) {
      if (!originals.has(node)) {
        if (!node.nodeValue.trim()) continue;
        const v = node.nodeValue;
        const k = v.trim().replace(/\s+/g, " ");
        originals.set(node, REVERSE[k] ? v.replace(v.trim(), REVERSE[k]) : v);
      }
      const src = originals.get(node);
      const key = src.trim().replace(/\s+/g, " ");
      const lead = src.match(/^\s*/)[0];
      const tail = src.match(/\s*$/)[0];
      node.nodeValue = lead + t(key) + tail;
    }

    document.querySelectorAll("[title], [aria-label]").forEach(el => {
      ["title", "aria-label"].forEach(attr => {
        if (!el.hasAttribute(attr)) return;
        const store = "i18n" + attr.replace("-", "");
        if (!(store in el.dataset)) el.dataset[store] = el.getAttribute(attr);
        el.setAttribute(attr, t(el.dataset[store]));
      });
    });

    if (!("i18nTitle" in document.documentElement.dataset)) document.documentElement.dataset.i18nTitle = document.title;
    document.title = t(document.documentElement.dataset.i18nTitle);
    document.documentElement.lang = LANGS[lang].html;
  }

  function setLang(next) {
    if (!LANGS[next] || next === lang) return;
    lang = next;
    try { localStorage.setItem(STORE_KEY, lang); } catch (_) {}
    translateDom();
    document.dispatchEvent(new CustomEvent("mat:langchange", { detail: { lang } }));
  }

  window.MAT_I18N = {
    t,
    setLang,
    translateDom,
    get lang() { return lang; },
    get dateLocale() { return LANGS[lang].date; },
    languages: Object.keys(LANGS).map(code => ({ code, label: LANGS[code].label }))
  };
})();
