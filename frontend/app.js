// Remote Antigravity Mobile Dashboard Client Logic
(function() {
  'use strict';

  // DOM Elements
  const elAppContainer = document.querySelector('.app-container');
  const elConnectionStatus = document.getElementById('connection-status');
  const elStatusText = document.getElementById('status-text');
  const elWorkspaceSelect = document.getElementById('workspace-select');
  const elTerminalBody = document.getElementById('terminal-body');
  const elLogCount = document.getElementById('log-count');
  const elPromptForm = document.getElementById('prompt-form');
  const elPromptInput = document.getElementById('prompt-input');
  const elBtnStopTask = document.getElementById('btn-stop-task');
  const elBtnViewDiff = document.getElementById('btn-view-diff');
  const elBtnClearLogs = document.getElementById('btn-clear-logs');
  
  // Plus Menu & Voice Controls
  const elBtnPlusMenu = document.getElementById('btn-plus-menu');
  const elBtnVoiceInput = document.getElementById('btn-voice-input');
  const elAttachmentPreview = document.getElementById('attachment-preview');
  const elModalPlus = document.getElementById('plus-action-modal');
  const elBtnClosePlus = document.getElementById('btn-close-plus');
  const elFileUploadInput = document.getElementById('file-upload-input');
  const elBtnMentionFile = document.getElementById('btn-mention-file');

  // File Picker Modal (@)
  const elModalFilePicker = document.getElementById('file-picker-modal');
  const elBtnCloseFilePicker = document.getElementById('btn-close-file-picker');
  const elFileSearchInput = document.getElementById('file-search-input');
  const elFileListContainer = document.getElementById('file-list-container');

  // Modals & Settings
  const elBtnSettings = document.getElementById('btn-settings');
  const elBtnCloseSettings = document.getElementById('btn-close-settings');
  const elBtnSaveSettings = document.getElementById('btn-save-settings');
  const elModalSettings = document.getElementById('settings-modal');
  const elInputBridgeUrl = document.getElementById('input-bridge-url');
  const elInputApiToken = document.getElementById('input-api-token');

  const elModalDiff = document.getElementById('diff-modal');
  const elBtnCloseDiff = document.getElementById('btn-close-diff');
  const elBtnCloseDiffBottom = document.getElementById('btn-close-diff-bottom');
  const elBtnRefreshDiff = document.getElementById('btn-refresh-diff');
  const elDiffContent = document.getElementById('diff-content');

  // Live Activity & Floating Scroll Elements
  const elBtnScrollBottom = document.getElementById('btn-scroll-bottom');
  const elScrollPillDot = document.getElementById('scroll-pill-dot');
  const elScrollPillText = document.getElementById('scroll-pill-text');
  const elTerminalLiveBadge = document.getElementById('terminal-live-badge');
  const elTerminalLiveActionText = document.getElementById('terminal-live-action-text');

  // Client Emoji Sanitizer
  function stripEmojis(str) {
    if (!str) return '';
    return str.replace(/[\u{1F300}-\u{1F9FF}]|[\u{1F600}-\u{1F64F}]|[\u{1F680}-\u{1F6FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]/gu, '').trim();
  }

  // Dynamic Bridge URL Resolver (Handles HTTPS Cloudflare Tunnels & Tailscale IPs)
  function getInitialBridgeUrl() {
    if (window.location.protocol === 'https:') {
      localStorage.removeItem('antigravity_bridge_url');
      return window.location.origin;
    }
    const saved = localStorage.getItem('antigravity_bridge_url');
    if (saved) return saved;

    if (!window.location.port && window.location.hostname !== 'localhost') {
      return `http://${window.location.hostname}:8900`;
    }
    return window.location.origin;
  }


  // One-Click onboarding: the setup script prints a link like
  //   http://100.x.y.z:8900/?token=XXXX
  // The token from the URL is stored locally so the user never has to type it.
  function captureTokenFromUrl() {
    try {
      const urlToken = new URLSearchParams(window.location.search).get('token');
      if (urlToken) {
        localStorage.setItem('antigravity_api_token', urlToken);
        window.history.replaceState({}, document.title, window.location.pathname);
      }
    } catch (e) {}
  }

  captureTokenFromUrl();

  // Application State
  let config = {
    bridgeUrl: getInitialBridgeUrl(),
    apiToken: localStorage.getItem('antigravity_api_token') || '',
    workspace: localStorage.getItem('antigravity_workspace') || ''
  };

  let socket = null;
  let lineCount = 0;
  let isRunning = false;
  let pingInterval = null;
  let authFailed = false;
  let lastChatHash = '';
  let pendingAttachments = [];
  let availableFiles = [];
  let recognition = null;
  let isRecording = false;

  // Scroll & Live Action State
  let userScrolledUp = false;
  let autoScrollEnabled = true;
  let currentRunningAction = '';
  const openedActionGroups = new Set();

  function isNearBottom() {
    if (!elTerminalBody) return true;
    const threshold = 70;
    return (elTerminalBody.scrollHeight - elTerminalBody.scrollTop - elTerminalBody.clientHeight) <= threshold;
  }

  function updateScrollFloatingButton() {
    if (!elBtnScrollBottom) return;

    if (userScrolledUp) {
      elBtnScrollBottom.classList.remove('hidden');
      if (isRunning && currentRunningAction) {
        if (elScrollPillDot) elScrollPillDot.classList.remove('hidden');
        if (elScrollPillText) elScrollPillText.textContent = `Antigravity: ${currentRunningAction}`;
      } else {
        if (elScrollPillDot) elScrollPillDot.classList.add('hidden');
        if (elScrollPillText) elScrollPillText.textContent = 'Neueste Nachricht';
      }
    } else {
      elBtnScrollBottom.classList.add('hidden');
    }

    if (elTerminalLiveBadge && elTerminalLiveActionText) {
      if (isRunning && currentRunningAction) {
        elTerminalLiveBadge.classList.remove('hidden');
        elTerminalLiveActionText.textContent = currentRunningAction;
      } else {
        elTerminalLiveBadge.classList.add('hidden');
      }
    }
  }

  let healthInterval = null;

  async function checkHealthAndSync() {
    try {
      const currentWs = config.workspace || (elWorkspaceSelect ? elWorkspaceSelect.value : '');
      const healthUrl = currentWs
        ? `${config.bridgeUrl}/health?token=${encodeURIComponent(config.apiToken)}&workspace=${encodeURIComponent(currentWs)}`
        : `${config.bridgeUrl}/health?token=${encodeURIComponent(config.apiToken)}`;
      const res = await fetch(healthUrl, {
        cache: 'no-store'
      });
      const contentType = res.headers.get('content-type') || '';
      if (contentType.includes('text/html')) {
        updateConnectionStatus('offline', 'Proxy/Login erforderlich');
        return false;
      }
      if (res.status === 401) {
        authFailed = true;
        updateConnectionStatus('offline', (config.apiToken || '').trim() ? 'Token ungültig' : 'Token fehlt');
        return false;
      }
      if (res.ok) {
        const data = await res.json();
        if (data.status === 'online') {
          authFailed = false;
          updateConnectionStatus('online', 'Verbunden');
          setTaskRunningState(data.agent_status === 'running');
          fetchProjectsList();
          refreshChatHistory();
          return true;
        }
      }
    } catch (e) {}
    return false;
  }

  async function refreshChatHistory() {
    try {
      const currentWs = config.workspace || (elWorkspaceSelect ? elWorkspaceSelect.value : '');
      const historyUrl = currentWs
        ? `${config.bridgeUrl}/chat/history?token=${encodeURIComponent(config.apiToken)}&workspace=${encodeURIComponent(currentWs)}`
        : `${config.bridgeUrl}/chat/history?token=${encodeURIComponent(config.apiToken)}`;
      const res = await fetch(historyUrl, {
        cache: 'no-store'
      });
      if (res.ok) {
        const data = await res.json();
        if (data.chat_messages && Array.isArray(data.chat_messages)) {
          renderChatHistory(data.chat_messages);
        }
      }
    } catch(e){}
  }

  function init() {
    setupEventListeners();
    setupVisualViewportHandler();
    populateSettingsInputs();
    initSpeechRecognition();

    if (!(config.apiToken || '').trim()) {
      appendLog('log-status', '[System] Kein Token gespeichert. Bitte die Onboarding-URL mit ?token=... öffnen oder das Token in den Einstellungen (⚙️) eintragen.');
    }

    checkHealthAndSync();
    connectWebSocket();
    fetchProjectsList();

    if (healthInterval) clearInterval(healthInterval);
    healthInterval = setInterval(checkHealthAndSync, 3000);
  }

  // iOS Keyboard Visual Viewport Fix
  function setupVisualViewportHandler() {
    if (window.visualViewport) {
      function onVisualViewportResize() {
        if (elTerminalBody && !userScrolledUp && isNearBottom()) {
          elTerminalBody.scrollTop = elTerminalBody.scrollHeight;
        }
      }
      window.visualViewport.addEventListener('resize', onVisualViewportResize);
    }
  }

  function autoResizeTextarea(textarea) {
    if (!textarea) return;
    if (!textarea.value) {
      textarea.style.height = '24px';
      return;
    }
    textarea.style.height = '24px';
    const newHeight = Math.min(textarea.scrollHeight, 80);
    textarea.style.height = `${newHeight}px`;
  }

  function populateSettingsInputs() {
    elInputBridgeUrl.value = config.bridgeUrl;
    elInputApiToken.value = config.apiToken;
  }

  function saveSettings() {
    config.bridgeUrl = elInputBridgeUrl.value.trim().replace(/\/$/, '');
    config.apiToken = elInputApiToken.value.trim();

    localStorage.setItem('antigravity_bridge_url', config.bridgeUrl);
    localStorage.setItem('antigravity_api_token', config.apiToken);

    appendLog('system-msg', `[System] Einstellungen gespeichert. Verbinde neu mit ${config.bridgeUrl}...`);
    closeModal(elModalSettings);
    connectWebSocket();
    fetchProjectsList();
  }

  // WebSocket Connection Manager
  function connectWebSocket() {
    if (socket) {
      socket.close();
      socket = null;
    }
    if (pingInterval) {
      clearInterval(pingInterval);
      pingInterval = null;
    }

    let wsUrl;
    try {
      const url = new URL(config.bridgeUrl);
      const wsProtocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
      wsUrl = `${wsProtocol}//${url.host}/ws/logs?token=${encodeURIComponent(config.apiToken)}`;
    } catch (e) {
      appendLog('log-stderr', `[Fehler] Ungültige Bridge-URL: ${config.bridgeUrl}`);
      checkHealthAndSync();
      return;
    }

    try {
      socket = new WebSocket(wsUrl);

      socket.onopen = function() {
        updateConnectionStatus('online', 'Verbunden');
        appendLog('system-msg', '[System] WebSocket-Verbindung hergestellt.');
        
        pingInterval = setInterval(() => {
          if (socket && socket.readyState === WebSocket.OPEN) {
            socket.send(JSON.stringify({ type: 'ping' }));
          }
        }, 20000);
      };

      socket.onmessage = function(event) {
        try {
          const msg = JSON.parse(event.data);
          handleWebSocketMessage(msg);
        } catch (err) {
          console.error("Message parse error:", err);
        }
      };

      socket.onerror = function() {
        checkHealthAndSync();
      };

      socket.onclose = function(event) {
        checkHealthAndSync();
        if (pingInterval) clearInterval(pingInterval);

        // Bei ungueltigem/fehlendem Token nicht endlos neu verbinden (spart Akku).
        if (authFailed) {
          appendLog('log-status', '[System] Verbindung gestoppt: Token fehlt oder ist ungültig (Einstellungen öffnen ⚙️).');
          return;
        }

        setTimeout(() => {
          if (!socket || socket.readyState === WebSocket.CLOSED) {
            connectWebSocket();
          }
        }, 6000);
      };
    } catch (err) {
      checkHealthAndSync();
      appendLog('log-stderr', `[Fehler] WebSocket Exception: ${err.message}`);
    }
  }

  function updateConnectionStatus(state, label) {
    elConnectionStatus.className = `status-badge status-${state}`;
    elStatusText.textContent = label;
  }

  function handleWebSocketMessage(msg) {
    if (msg.type === 'init') {
      const data = msg.data || {};
      if (data.workspace) {
        config.workspace = data.workspace;
      }
      setTaskRunningState(data.status === 'running');
      if (data.chat_messages && Array.isArray(data.chat_messages)) {
        renderChatHistory(data.chat_messages);
      }
      if (data.history && Array.isArray(data.history)) {
        data.history.forEach(item => {
          try {
            const parsedData = typeof item.data === 'string' ? JSON.parse(item.data) : item.data;
            if (item.type === 'log') {
              appendLog(parsedData.stream === 'stderr' ? 'log-stderr' : 'log-stdout', stripEmojis(parsedData.text));
            } else if (item.type === 'status') {
              appendLog('log-status', `[Status] ${stripEmojis(parsedData.message)}`);
            }
          } catch(e){}
        });
      }
    } else if (msg.type === 'chat_update') {
      const data = msg.data || {};
      if (data.chat_messages && Array.isArray(data.chat_messages)) {
        renderChatHistory(data.chat_messages);
      }
    } else if (msg.type === 'log') {
      const data = msg.data;
      appendLog(data.stream === 'stderr' ? 'log-stderr' : 'log-stdout', stripEmojis(data.text));
    } else if (msg.type === 'status') {
      const data = msg.data;
      appendLog('log-status', `[Status] ${stripEmojis(data.message)}`);
      if (msg.status) {
        setTaskRunningState(msg.status === 'running');
      }
    }
  }

  function renderChatHistory(messages) {
    const currentHash = JSON.stringify(messages);
    if (currentHash === lastChatHash) return;
    lastChatHash = currentHash;

    const wasScrolledUp = userScrolledUp || !isNearBottom();
    const prevScrollTop = elTerminalBody.scrollTop;

    // Determine current active action
    let latestAction = '';
    for (let i = messages.length - 1; i >= 0; i--) {
      const clean = stripEmojis(messages[i].text);
      if (clean && clean.startsWith('[Aktion]:')) {
        latestAction = clean.replace('[Aktion]:', '').trim();
        break;
      }
    }
    currentRunningAction = isRunning ? latestAction : '';

    elTerminalBody.innerHTML = '';
    lineCount = 0;

    const sysMsg = document.createElement('div');
    sysMsg.className = 'log-entry system-msg';
    sysMsg.textContent = '[System] Aktuelle Antigravity-Konversation synchronisiert:';
    elTerminalBody.appendChild(sysMsg);

    // Group consecutive [Aktion]: messages
    const processedItems = [];
    for (let i = 0; i < messages.length; i++) {
      const m = messages[i];
      const cleanText = stripEmojis(m.text);
      if (!cleanText) continue;

      if (cleanText.startsWith('[Aktion]:')) {
        const actionText = cleanText.replace('[Aktion]:', '').trim();
        const prevItem = processedItems[processedItems.length - 1];
        if (prevItem && prevItem.type === 'action_group') {
          prevItem.actions.push(actionText);
          prevItem.lastIndex = i;
        } else {
          processedItems.push({
            type: 'action_group',
            actions: [actionText],
            firstIndex: i,
            lastIndex: i
          });
        }
      } else {
        processedItems.push({
          type: 'message',
          role: m.role,
          text: cleanText,
          index: i
        });
      }
    }

    processedItems.forEach(item => {
      if (item.type === 'message') {
        const entry = document.createElement('div');
        if (item.role === 'user') {
          entry.className = 'log-entry chat-user-msg';
          entry.innerHTML = `<span class="chat-role user-role">Du:</span> ${escapeHtml(item.text)}`;
        } else {
          entry.className = 'log-entry chat-assistant-msg';
          const formattedMarkdown = window.marked ? marked.parse(item.text) : escapeHtml(item.text);
          entry.innerHTML = `<span class="chat-role ai-role">Antigravity:</span> <div class="markdown-body">${formattedMarkdown}</div>`;
        }
        elTerminalBody.appendChild(entry);
        lineCount++;
      } else if (item.type === 'action_group') {
        const isCurrentActive = (item.lastIndex === messages.length - 1) && isRunning;
        const count = item.actions.length;
        const lastActionInGroup = item.actions[item.actions.length - 1];

        if (count === 1) {
          const entry = document.createElement('div');
          entry.className = 'log-entry action-single-entry';
          const dotClass = isCurrentActive ? 'action-pulse-dot' : 'action-done-dot';
          entry.innerHTML = `<div class="action-status-pill"><span class="${dotClass}"></span> <span class="action-pill-text">${escapeHtml(lastActionInGroup)}</span></div>`;
          elTerminalBody.appendChild(entry);
        } else {
          const groupKey = `ag_${item.firstIndex}`;
          const details = document.createElement('details');
          details.className = 'action-group-details';
          if (openedActionGroups.has(groupKey)) {
            details.open = true;
          }
          details.addEventListener('toggle', () => {
            if (details.open) {
              openedActionGroups.add(groupKey);
            } else {
              openedActionGroups.delete(groupKey);
            }
          });

          const titleLabel = isCurrentActive ? 'Antigravity arbeitet' : 'Antigravity Schritte';
          const dotClass = isCurrentActive ? 'action-pulse-dot' : 'action-done-dot';

          details.innerHTML = `
            <summary class="action-group-summary">
              <div class="action-group-title">
                <span class="${dotClass}"></span>
                <span class="action-group-label">${titleLabel} (${count})</span>
              </div>
              <div class="action-group-latest">${escapeHtml(lastActionInGroup)}</div>
              <span class="action-group-chevron">▾</span>
            </summary>
            <div class="action-group-content">
              ${item.actions.map((act, idx) => {
                const isStepActive = (idx === item.actions.length - 1) && isCurrentActive;
                const stepDotClass = isStepActive ? 'action-pulse-dot' : 'action-done-dot';
                return `
                  <div class="action-step-item ${isStepActive ? 'active-step' : ''}">
                    <span class="${stepDotClass}"></span>
                    <span class="action-step-name">${escapeHtml(act)}</span>
                  </div>
                `;
              }).join('')}
            </div>
          `;
          elTerminalBody.appendChild(details);
        }
        lineCount++;
      }
    });

    elTerminalBody.querySelectorAll('pre').forEach(pre => {
      if (!pre.querySelector('.copy-code-btn')) {
        const copyBtn = document.createElement('button');
        copyBtn.className = 'copy-code-btn';
        copyBtn.textContent = 'Kopieren';
        copyBtn.onclick = function() {
          const codeText = pre.querySelector('code') ? pre.querySelector('code').innerText : pre.innerText;
          copyToClipboard(codeText).then(ok => {
            copyBtn.textContent = ok ? 'Kopiert' : 'Kopieren fehlgeschlagen';
            setTimeout(() => copyBtn.textContent = 'Kopieren', 2000);
          });
        };
        pre.appendChild(copyBtn);
      }
    });

    if (window.Prism) Prism.highlightAllUnder(elTerminalBody);

    elLogCount.textContent = `${messages.length} Nachrichten`;

    if (wasScrolledUp) {
      elTerminalBody.scrollTop = prevScrollTop;
    } else {
      elTerminalBody.scrollTop = elTerminalBody.scrollHeight;
    }

    updateScrollFloatingButton();
  }

  function escapeHtml(str) {
    if (typeof str !== 'string') return '';
    return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  // Clipboard-Zugriff mit Fallback.
  // navigator.clipboard existiert nur in "secure contexts" (https oder localhost).
  // Ueber http://100.x.y.z (Tailscale) ist es undefined -> klassischer Fallback.
  function copyToClipboard(text) {
    try {
      if (navigator.clipboard && window.isSecureContext) {
        return navigator.clipboard.writeText(text).then(
          () => true,
          () => legacyCopy(text)
        );
      }
    } catch (e) {}
    return Promise.resolve(legacyCopy(text));
  }

  function legacyCopy(text) {
    try {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.setAttribute('readonly', '');
      ta.style.position = 'fixed';
      ta.style.top = '-1000px';
      document.body.appendChild(ta);
      ta.select();
      ta.setSelectionRange(0, ta.value.length);
      const ok = document.execCommand('copy');
      document.body.removeChild(ta);
      return ok;
    } catch (e) {
      return false;
    }
  }

  function setTaskRunningState(running) {
    isRunning = running;
    elBtnStopTask.disabled = !running;
    if (running) {
      updateConnectionStatus('running', 'Task läuft...');
    } else {
      updateConnectionStatus('online', 'Bereit');
      currentRunningAction = '';
    }
    updateScrollFloatingButton();
  }

  function appendLog(cssClass, text) {
    const wasScrolledUp = userScrolledUp || !isNearBottom();
    const line = document.createElement('div');
    line.className = `log-entry ${cssClass}`;
    
    const timeSpan = document.createElement('span');
    timeSpan.className = 'log-time';
    const now = new Date();
    timeSpan.textContent = `[${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}:${now.getSeconds().toString().padStart(2, '0')}]`;
    
    line.appendChild(timeSpan);
    line.appendChild(document.createTextNode(stripEmojis(text)));

    elTerminalBody.appendChild(line);
    lineCount++;
    elLogCount.textContent = `${lineCount} Zeilen`;

    if (elTerminalBody.children.length > 500) {
      elTerminalBody.removeChild(elTerminalBody.firstChild);
    }

    if (!wasScrolledUp) {
      elTerminalBody.scrollTop = elTerminalBody.scrollHeight;
    }
    updateScrollFloatingButton();
  }

  // Projects & Workspace Management
  let lastProjectsHash = '';

  async function fetchProjectsList() {
    try {
      const res = await fetch(`${config.bridgeUrl}/projects?token=${encodeURIComponent(config.apiToken)}`, {
        cache: 'no-store',
        credentials: 'same-origin'
      });
      if (!res.ok) return;
      const data = await res.json();
      const currentProjects = data.projects || [];
      const newHash = JSON.stringify(currentProjects) + (data.current || '');

      if (newHash !== lastProjectsHash || elWorkspaceSelect.options.length <= 1) {
        lastProjectsHash = newHash;
        const selectedValue = config.workspace || data.current;
        elWorkspaceSelect.innerHTML = '';

        currentProjects.forEach(p => {
          const opt = document.createElement('option');
          opt.value = p.path;
          opt.textContent = p.name;
          if (p.path.toLowerCase() === (selectedValue || '').toLowerCase()) {
            opt.selected = true;
          }
          elWorkspaceSelect.appendChild(opt);
        });

        if (!config.workspace && elWorkspaceSelect.value) {
          config.workspace = elWorkspaceSelect.value;
          localStorage.setItem('antigravity_workspace', config.workspace);
        }
      }
    } catch(e){}
  }

  async function changeWorkspace(newPath) {
    if (!newPath) return;
    try {
      config.workspace = newPath;
      localStorage.setItem('antigravity_workspace', newPath);
      lastChatHash = '';

      const optText = elWorkspaceSelect.options[elWorkspaceSelect.selectedIndex]?.textContent || newPath;
      appendLog('system-msg', `[System] Wechsle zu Projekt: ${optText}...`);

      const res = await fetch(`${config.bridgeUrl}/action`, {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'X-API-Token': config.apiToken
        },
        body: JSON.stringify({ action: 'change_workspace', params: { workspace: newPath } })
      });
      if (res.ok) {
        refreshChatHistory();
        fetchWorkspaceFiles();
        if (socket && socket.readyState === WebSocket.OPEN) {
          socket.send(JSON.stringify({ type: 'refresh_chat', workspace: newPath }));
        }
      }
    } catch(e){}
  }

  // Voice Input (Speech-to-Text)
  function initSpeechRecognition() {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognition) {
      elBtnVoiceInput.style.display = 'none';
      return;
    }

    recognition = new SpeechRecognition();
    recognition.lang = 'de-DE';
    recognition.continuous = false;
    recognition.interimResults = false;

    recognition.onstart = function() {
      isRecording = true;
      elBtnVoiceInput.classList.add('recording');
      elBtnVoiceInput.title = 'Aufnahme läuft... (Tippen zum Stoppen)';
    };

    recognition.onresult = function(event) {
      const transcript = event.results[0][0].transcript;
      if (transcript) {
        elPromptInput.value += (elPromptInput.value ? ' ' : '') + transcript;
        autoResizeTextarea(elPromptInput);
      }
    };

    recognition.onerror = function(event) {
      appendLog('log-stderr', `[Spracheingabe-Fehler] ${event.error}`);
      stopRecording();
    };

    recognition.onend = function() {
      stopRecording();
    };
  }

  function toggleVoiceRecording() {
    if (!recognition) return;
    if (isRecording) {
      recognition.stop();
    } else {
      try {
        recognition.start();
      } catch(e) {
        stopRecording();
      }
    }
  }

  function stopRecording() {
    isRecording = false;
    elBtnVoiceInput.classList.remove('recording');
    elBtnVoiceInput.title = 'Spracheingabe';
  }

  // File Upload Attachments
  async function handleFileUpload(files) {
    if (!files || files.length === 0) return;
    closeModal(elModalPlus);

    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const formData = new FormData();
      formData.append('file', file);

      try {
        appendLog('system-msg', `[Upload] Lade ${file.name} hoch...`);
        const res = await fetch(`${config.bridgeUrl}/upload`, {
          method: 'POST',
          credentials: 'same-origin',
          headers: { 'X-API-Token': config.apiToken },
          body: formData
        });
        if (res.ok) {
          const data = await res.json();
          pendingAttachments.push(data.filename);
          renderAttachmentsPreview();
        }
      } catch(err) {
        appendLog('log-stderr', `[Upload Fehler] ${err.message}`);
      }
    }
  }

  function renderAttachmentsPreview() {
    if (pendingAttachments.length === 0) {
      elAttachmentPreview.classList.add('hidden');
      elAttachmentPreview.innerHTML = '';
      return;
    }
    elAttachmentPreview.classList.remove('hidden');
    elAttachmentPreview.innerHTML = '';
    pendingAttachments.forEach((att, idx) => {
      const chip = document.createElement('span');
      chip.className = 'attachment-chip';
      chip.innerHTML = `[Datei: ${att}] <b style="cursor:pointer" onclick="removeAttachment(${idx})">✕</b>`;
      elAttachmentPreview.appendChild(chip);
    });
  }

  window.removeAttachment = function(idx) {
    pendingAttachments.splice(idx, 1);
    renderAttachmentsPreview();
  };

  // Workspace File Picker (@)
  async function openFilePickerModal() {
    closeModal(elModalPlus);
    openModal(elModalFilePicker);
    elFileListContainer.textContent = 'Lade Dateien...';

    try {
      const res = await fetch(`${config.bridgeUrl}/workspace/files?token=${encodeURIComponent(config.apiToken)}`, {
        cache: 'no-store',
        credentials: 'same-origin'
      });
      if (res.ok) {
        const data = await res.json();
        availableFiles = data.files || [];
        renderFileList(availableFiles);
      } else if (res.status === 401) {
        elFileListContainer.textContent = 'Token ungültig - bitte in den Einstellungen (⚙️) prüfen.';
      } else {
        elFileListContainer.textContent = `Fehler beim Laden der Dateien (HTTP ${res.status}).`;
      }
    } catch(e) {
      elFileListContainer.textContent = 'Fehler beim Laden der Dateien.';
    }
  }

  function renderFileList(files) {
    elFileListContainer.innerHTML = '';
    if (files.length === 0) {
      elFileListContainer.textContent = 'Keine Dateien gefunden.';
      return;
    }
    files.forEach(file => {
      const item = document.createElement('div');
      item.className = 'file-picker-item';
      item.textContent = `@${file}`;
      item.onclick = function() {
        elPromptInput.value += (elPromptInput.value ? ' ' : '') + `@${file}`;
        autoResizeTextarea(elPromptInput);
        closeModal(elModalFilePicker);
      };
      elFileListContainer.appendChild(item);
    });
  }

  // Send Prompt with attachments
  async function sendPrompt(promptText) {
    if (!promptText && pendingAttachments.length === 0) return;

    let fullPrompt = promptText;

    if (pendingAttachments.length > 0) {
      fullPrompt += ` (Angefügte Dateien: ${pendingAttachments.join(', ')})`;
    }

    lastChatHash = '';
    elPromptInput.value = '';
    pendingAttachments = [];
    renderAttachmentsPreview();
    autoResizeTextarea(elPromptInput);

    userScrolledUp = false;
    autoScrollEnabled = true;
    elTerminalBody.scrollTop = elTerminalBody.scrollHeight;
    updateScrollFloatingButton();

    try {
      const targetWs = config.workspace || (elWorkspaceSelect ? elWorkspaceSelect.value : '');
      const res = await fetch(`${config.bridgeUrl}/prompt`, {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'X-API-Token': config.apiToken
        },
        body: JSON.stringify({
          prompt: fullPrompt,
          workspace: targetWs || undefined
        })
      });

      if (!res.ok) {
        const errData = await res.json();
        throw new Error(errData.detail || 'Fehler beim Senden des Prompts');
      }

      const result = await res.json().catch(() => ({}));
      if (result.delivered === false) {
        appendLog('log-stderr', result.agentapi_available
          ? '[Fehler] Antigravity hat den Prompt nicht angenommen. Läuft die IDE mit geöffnetem Chat?'
          : '[Fehler] agentapi.bat fehlt - bitte die Antigravity IDE einmal normal starten.');
      }

      setTaskRunningState(true);
      setTimeout(refreshChatHistory, 300);
    } catch (err) {
      appendLog('log-stderr', `[Fehler] ${err.message}`);
    }
  }

  async function stopTask() {
    try {
      const res = await fetch(`${config.bridgeUrl}/action`, {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'X-API-Token': config.apiToken
        },
        body: JSON.stringify({ action: 'stop' })
      });
      const data = await res.json();
      appendLog('system-msg', `[Action] ${data.status}`);
      setTaskRunningState(false);
    } catch (err) {
      appendLog('log-stderr', `[Fehler beim Stoppen] ${err.message}`);
    }
  }

  async function fetchGitDiff() {
    openModal(elModalDiff);
    elDiffContent.textContent = 'Lade Git Diff vom PC...';
    try {
      const res = await fetch(`${config.bridgeUrl}/workspace/git-diff?token=${encodeURIComponent(config.apiToken)}`, {
        cache: 'no-store',
        credentials: 'same-origin'
      });
      if (!res.ok) throw new Error('Konnte Git Diff nicht abrufen');
      const data = await res.json();
      if (data.diff && data.diff.trim() !== '') {
        renderColoredDiff(data.diff);
      } else {
        elDiffContent.textContent = 'Keine nicht committeten Änderungen im Workspace vorhanden.';
      }
    } catch (err) {
      elDiffContent.textContent = `Fehler: ${err.message}`;
    }
  }

  function renderColoredDiff(diffText) {
    elDiffContent.innerHTML = '';
    const lines = diffText.split('\n');
    lines.forEach(line => {
      const lineSpan = document.createElement('div');
      if (line.startsWith('+') && !line.startsWith('+++')) {
        lineSpan.className = 'diff-add';
      } else if (line.startsWith('-') && !line.startsWith('---')) {
        lineSpan.className = 'diff-del';
      }
      lineSpan.textContent = line;
      elDiffContent.appendChild(lineSpan);
    });
  }

  function openModal(el) { el.classList.remove('hidden'); }
  function closeModal(el) { el.classList.add('hidden'); }

  function setupEventListeners() {
    const isMobileDevice = () => {
      return (window.innerWidth <= 768) || ('ontouchstart' in window) || (navigator.maxTouchPoints > 0);
    };

    elPromptForm.addEventListener('submit', function(e) {
      e.preventDefault();
      sendPrompt(elPromptInput.value.trim());
      if (isMobileDevice()) {
        elPromptInput.blur();
      }
    });

    elPromptInput.addEventListener('keydown', function(e) {
      if (e.key === 'Enter') {
        if (isMobileDevice()) {
          // On Mobile/Smartphone: Enter key creates a new line, does NOT send.
          return;
        }
        if (!e.shiftKey) {
          e.preventDefault();
          sendPrompt(elPromptInput.value.trim());
        }
      }
    });

    elPromptInput.addEventListener('input', function() {
      autoResizeTextarea(this);
    });

    elBtnPlusMenu.addEventListener('click', () => openModal(elModalPlus));
    elBtnClosePlus.addEventListener('click', () => closeModal(elModalPlus));
    elBtnVoiceInput.addEventListener('click', toggleVoiceRecording);

    elFileUploadInput.addEventListener('change', function() {
      handleFileUpload(this.files);
    });

    elBtnMentionFile.addEventListener('click', openFilePickerModal);
    elBtnCloseFilePicker.addEventListener('click', () => closeModal(elModalFilePicker));

    elFileSearchInput.addEventListener('input', function() {
      const q = this.value.toLowerCase().trim();
      const filtered = availableFiles.filter(f => f.toLowerCase().includes(q));
      renderFileList(filtered);
    });

    document.querySelectorAll('.btn-slash').forEach(btn => {
      btn.addEventListener('click', function() {
        const slashCmd = this.getAttribute('data-slash');
        elPromptInput.value = slashCmd + elPromptInput.value;
        autoResizeTextarea(elPromptInput);
        closeModal(elModalPlus);
      });
    });

    document.querySelectorAll('.chip-btn').forEach(btn => {
      btn.addEventListener('click', function() {
        const actionText = this.getAttribute('data-action');
        if (elPromptInput) {
          if (!elPromptInput.value.startsWith(actionText)) {
            elPromptInput.value = actionText + elPromptInput.value;
          }
          elPromptInput.focus();
          autoResizeTextarea(elPromptInput);
        }
      });
    });

    elWorkspaceSelect.addEventListener('change', function() {
      changeWorkspace(this.value);
    });

    elBtnStopTask.addEventListener('click', stopTask);
    elBtnViewDiff.addEventListener('click', fetchGitDiff);
    elBtnClearLogs.addEventListener('click', () => {
      elTerminalBody.innerHTML = '';
      lineCount = 0;
      userScrolledUp = false;
      currentRunningAction = '';
      elLogCount.textContent = '0 Zeilen';
      appendLog('system-msg', '[System] Anzeige geleert.');
      updateScrollFloatingButton();
    });

    // Terminal Scroll Tracking & Floating Pill Actions
    let scrollRaf = null;
    elTerminalBody.addEventListener('scroll', () => {
      if (scrollRaf) cancelAnimationFrame(scrollRaf);
      scrollRaf = requestAnimationFrame(() => {
        const nearBottom = isNearBottom();
        if (nearBottom) {
          userScrolledUp = false;
        } else {
          userScrolledUp = true;
        }
        updateScrollFloatingButton();
      });
    }, { passive: true });

    if (elBtnScrollBottom) {
      elBtnScrollBottom.addEventListener('click', () => {
        userScrolledUp = false;
        autoScrollEnabled = true;
        elTerminalBody.scrollTo({
          top: elTerminalBody.scrollHeight,
          behavior: 'smooth'
        });
        updateScrollFloatingButton();
      });
    }

    if (elTerminalLiveBadge) {
      elTerminalLiveBadge.addEventListener('click', () => {
        userScrolledUp = false;
        autoScrollEnabled = true;
        elTerminalBody.scrollTo({
          top: elTerminalBody.scrollHeight,
          behavior: 'smooth'
        });
        updateScrollFloatingButton();
      });
    }

    elBtnSettings.addEventListener('click', () => openModal(elModalSettings));
    elBtnCloseSettings.addEventListener('click', () => closeModal(elModalSettings));
    elBtnSaveSettings.addEventListener('click', saveSettings);

    elBtnCloseDiff.addEventListener('click', () => closeModal(elModalDiff));
    elBtnCloseDiffBottom.addEventListener('click', () => closeModal(elModalDiff));
    elBtnRefreshDiff.addEventListener('click', fetchGitDiff);

    [elModalSettings, elModalDiff, elModalPlus, elModalFilePicker].forEach(modal => {
      if (modal) {
        modal.addEventListener('click', (e) => {
          if (e.target === modal) closeModal(modal);
        });
      }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();
