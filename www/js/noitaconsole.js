// =============================================================================
// noitaconsole.js - Noita Web Console Client (v2.0)
// =============================================================================
// Features:
//   - WebSocket connection to Noita (ws://localhost:9777)
//   - CodeMirror multi-line editor (Shift+Enter to run)
//   - Single-line REPL (Enter to run, Tab to complete, Up/Down for history)
//   - xterm.js terminal output with ANSI color
//   - Auto-reconnect with exponential backoff
//   - Connection status indicator
//   - localStorage command history persistence
//   - Ctrl+L clear screen, !connect to change server
// =============================================================================

$(function(){
  initCodeMirror();
  initConnection();
});

// ===========================================================================
// State
// ===========================================================================
var codeWindow = null;
var connection = null;
var connected = false;
var repl = null;
var lineWindow = null;
var fit = null;

var commandHistory = [];
var HISTORY_KEY = 'noitaconsole_history';
var MAX_HISTORY = 200;

// Reconnect state
var reconnectAttempt = 0;
var maxReconnectAttempts = 20;
var reconnectBaseDelay = 1000;   // 1s
var reconnectMaxDelay = 30000;   // 30s
var reconnectTimer = null;
var reconnectEnabled = true;

// ===========================================================================
// ANSI Color Helpers
// ===========================================================================
function ansiRGB(r, g, b) {
  return `\x1b[38;2;${r};${g};${b}m`;
}

function ansiBgRGB(r, g, b) {
  return `\x1b[48;2;${r};${g};${b}m`;
}

function ansiReset() {
  return '\x1b[0m';
}

function ansiBold() {
  return '\x1b[1m';
}

// ===========================================================================
// LocalStorage History
// ===========================================================================
function loadHistory() {
  try {
    var stored = localStorage.getItem(HISTORY_KEY);
    if (stored) {
      commandHistory = JSON.parse(stored);
    }
  } catch(e) {
    console.warn('Failed to load history:', e);
  }
}

function saveHistory() {
  try {
    // Trim to max size
    if (commandHistory.length > MAX_HISTORY) {
      commandHistory = commandHistory.slice(-MAX_HISTORY);
    }
    localStorage.setItem(HISTORY_KEY, JSON.stringify(commandHistory));
  } catch(e) {
    console.warn('Failed to save history:', e);
  }
}

// ===========================================================================
// Token from URL
// ===========================================================================
function getToken() {
  var urlParams = new URLSearchParams(window.location.search);
  return urlParams.get('token');
}

// ===========================================================================
// Connection Management
// ===========================================================================
function computeReconnectDelay() {
  var delay = reconnectBaseDelay * Math.pow(2, reconnectAttempt);
  return Math.min(delay, reconnectMaxDelay);
}

function scheduleReconnect() {
  if (!reconnectEnabled) return;
  if (reconnectAttempt >= maxReconnectAttempts) {
    replPrint('SYS> Max reconnect attempts reached. Click Reconnect to try again.');
    updateStatus('disconnected', 'Max retries');
    return;
  }
  var delay = computeReconnectDelay();
  updateStatus('reconnecting', 'Retry in ' + Math.round(delay/1000) + 's');
  replPrint('SYS> Reconnecting in ' + Math.round(delay/1000) + 's (attempt ' + (reconnectAttempt + 1) + '/' + maxReconnectAttempts + ')...');
  clearTimeout(reconnectTimer);
  reconnectTimer = setTimeout(function() {
    initConnection();
  }, delay);
}

function updateStatus(state, msg) {
  var el = document.getElementById('status');
  if (!el) return;
  el.className = 'status-' + state;
  el.textContent = state.toUpperCase() + (msg ? ': ' + msg : '');
}

function initConnection(url) {
  if (!url) {
    url = 'ws://localhost:9777';
  }

  // Close existing connection
  if (connection) {
    try { connection.close(); } catch(e) {}
    connection = null;
  }

  updateStatus('connecting', url);
  console.log('Connecting to ' + url);

  try {
    connection = new WebSocket(url);
  } catch(e) {
    replPrint('ERR> Failed to create WebSocket: ' + e.message);
    reconnectAttempt++;
    scheduleReconnect();
    return;
  }

  connection.addEventListener('open', function (event) {
    console.log('Connected: ' + url);
    connected = true;
    reconnectAttempt = 0;
    clearTimeout(reconnectTimer);
    reconnectEnabled = true;

    var token = getToken();
    connection.send('AUTH "' + (token || '') + '"');
    replPrint('SYS> Connected to ' + url + '. Authenticating...');
    updateStatus('connected');
  });

  connection.addEventListener('close', function (event) {
    var wasConnected = connected;
    connected = false;
    connection = null;

    if (wasConnected) {
      replPrint('SYS> Disconnected (code: ' + event.code + ')');
    } else {
      replPrint('SYS> Connection failed');
    }
    reconnectAttempt++;
    scheduleReconnect();
  });

  connection.addEventListener('error', function (event) {
    // close event will follow
    updateStatus('error', 'Connection error');
  });

  connection.addEventListener('message', function (event) {
    replPrint(event.data);
  });
}

// ===========================================================================
// Manual reconnect (called from UI)
// ===========================================================================
function manualReconnect() {
  reconnectAttempt = 0;
  reconnectEnabled = true;
  clearTimeout(reconnectTimer);
  if (connection) {
    try { connection.close(); } catch(e) {}
    connection = null;
    connected = false;
  }
  initConnection();
}

function stopReconnecting() {
  reconnectEnabled = false;
  reconnectAttempt = maxReconnectAttempts;
  clearTimeout(reconnectTimer);
  updateStatus('disconnected', 'Reconnect stopped');
}

// ===========================================================================
// Code Execution
// ===========================================================================
function remoteEval(code) {
  if (!code || code.trim() === '') return;

  // Local commands (prefixed with !)
  if (code[0] === '!') {
    let parts = code.slice(1).trim().split(/\s+/);
    switch (parts[0]) {
      case 'connect':
        if (parts[1]) {
          initConnection(parts[1]);
        }
        break;
      case 'reconnect':
        manualReconnect();
        break;
      case 'stop':
        stopReconnecting();
        break;
      case 'clear':
        clearTerminal();
        break;
      default:
        replPrint('UNKNOWN> Unknown local command: ' + parts[0]);
        replPrint('UNKNOWN> Available: !connect <url>, !reconnect, !stop, !clear');
    }
    return;
  }

  if (connected && connection && connection.readyState === WebSocket.OPEN) {
    connection.send(code);
  } else {
    replPrint('ERR> Not connected. Type !reconnect to try again.');
  }
}

// ===========================================================================
// Terminal Output
// ===========================================================================
function clearTerminal() {
  if (repl && repl._initialized) {
    repl.clear();
    repl.writeln(ansiRGB(100, 255, 100) + '[Screen cleared]' + ansiReset());
    repl.writeln('');
  }
}

function replPrint(message) {
  if (!repl || !repl._initialized) return;

  message = message.replace(/\n/g, '\r\n');

  // Color-code by message prefix
  if (message.indexOf('ERR>') === 0) {
    message = ansiRGB(255, 60, 60) + ansiBold() + message + ansiReset();
  } else if (message.indexOf('RES>') === 0) {
    message = ansiRGB(100, 180, 255) + message + ansiReset();
  } else if (message.indexOf('EVAL>') === 0) {
    message = ansiRGB(140, 255, 140) + message + ansiReset();
  } else if (message.indexOf('HELP>') === 0) {
    message = ansiRGB(200, 255, 200) + message + ansiReset();
  } else if (message.indexOf('GAME>') === 0) {
    message = ansiRGB(210, 210, 210) + message + ansiReset();
  } else if (message.indexOf('SYS>') === 0) {
    message = ansiRGB(255, 200, 100) + message + ansiReset();
  } else if (message.indexOf('COM>') === 0) {
    // Tab completion response: extract options and apply
    let parts = message.slice(4).split(' ');
    let prefix = parts[0];
    let opts = parts.slice(1).join(' ').split(',');
    if (opts.length === 1 && opts[0] !== '') {
      // Single match: auto-fill
      lineWindow.setValue(prefix + opts[0]);
      lineWindow.setCursor(lineWindow.lineCount(), 0);
    } else if (opts.length > 1) {
      // Multiple matches: fill common prefix + show options
      let completion = longestSetPrefix(opts);
      lineWindow.setValue(prefix + completion);
      lineWindow.setCursor(lineWindow.lineCount(), 0);
      // Show completions in output
      repl.writeln(ansiRGB(150, 150, 150) + '--- Completions ---' + ansiReset());
      for (var i = 0; i < opts.length; i++) {
        repl.writeln(ansiRGB(150, 150, 150) + '  ' + opts[i] + ansiReset());
      }
    }
    return; // Don't print COM> raw message
  } else if (message.indexOf('UNKNOWN>') === 0) {
    message = ansiRGB(255, 150, 0) + message + ansiReset();
  }

  repl.writeln(message);
}

// ===========================================================================
// String Utility
// ===========================================================================
function longestSharedPrefix(a, b) {
  var nchars = Math.min(a.length, b.length);
  var prefixLength = 0;
  for (prefixLength = 0; prefixLength < nchars; ++prefixLength) {
    if (a[prefixLength] !== b[prefixLength]) {
      break;
    }
  }
  return a.slice(0, prefixLength);
}

function longestSetPrefix(opts) {
  if (opts.length === 0) return '';
  var curPrefix = opts[0];
  for (var idx = 1; idx < opts.length; ++idx) {
    curPrefix = longestSharedPrefix(curPrefix, opts[idx]);
  }
  return curPrefix;
}

// ===========================================================================
// CodeMirror Initialization
// ===========================================================================
function initCodeMirror() {
  // Multi-line editor
  codeWindow = CodeMirror.fromTextArea(document.getElementById('code'), {
    value: '-- Multi-line Lua code here\n-- Shift+Enter to run\nfor i = 1, 5 do\n  print(i)\nend',
    mode: 'lua',
    theme: 'dracula',
    lineNumbers: true,
    tabSize: 2,
  });

  codeWindow.setOption('extraKeys', {
    'Shift-Enter': function(cm) {
      remoteEval(cm.getValue());
      replPrint('EVAL> [multi-line buffer]');
    },
    'Tab': function(cm) {
      cm.execCommand('insertSoftTab');
    },
  });

  // Single-line REPL
  lineWindow = CodeMirror.fromTextArea(document.getElementById('replinput'), {
    value: '',
    mode: 'lua',
    theme: 'dracula',
  });

  lineWindow.setOption('extraKeys', {
    'Enter': function(cm) {
      var val = cm.getValue().trim();
      if (val === '') return;

      // Trailing ? = help shortcut
      if (val.slice(-1) === '?') {
        val = 'help("' + val.slice(0, -1) + '")';
      }

      remoteEval(val);

      // History management
      var idx = commandHistory.indexOf(val);
      if (idx >= 0) {
        // Move to end
        commandHistory.splice(idx, 1);
      }
      commandHistory.push(val);
      if (commandHistory.length > MAX_HISTORY) {
        commandHistory.shift();
      }
      saveHistory();

      replPrint('EVAL> ' + val);
      cm.setValue('');
    },
    'Tab': function(cm) {
      var val = cm.getValue().trim();
      if (val === '') return;
      // Send tab-completion request to server
      remoteEval('complete([=[' + val + ']=])');
    },
    'Up': function(cm) {
      var current = cm.getValue();
      var hpos = commandHistory.lastIndexOf(current);
      if (hpos > 0) {
        cm.setValue(commandHistory[hpos - 1]);
      } else if (hpos === 0) {
        // Already at oldest, stay
      } else {
        // Not in history: go to last
        if (commandHistory.length > 0) {
          cm.setValue(commandHistory[commandHistory.length - 1]);
        }
      }
      cm.setCursor(cm.lineCount(), 0);
    },
    'Down': function(cm) {
      var current = cm.getValue();
      var hpos = commandHistory.indexOf(current);
      if (hpos >= 0 && hpos < commandHistory.length - 1) {
        cm.setValue(commandHistory[hpos + 1]);
      } else {
        cm.setValue('');
      }
      cm.setCursor(cm.lineCount(), 0);
    },
    'Ctrl-L': function(cm) {
      clearTerminal();
    },
  });

  // Terminal output
  repl = new Terminal({
    theme: {
      background: '#111',
      foreground: '#ccc',
    },
    fontSize: 13,
    cursorBlink: true,
    allowProposedApi: true,
  });
  fit = new FitAddon.FitAddon();
  repl.loadAddon(fit);
  repl.open(document.getElementById('repl'));
  repl._initialized = true;

  fit.fit();

  // Load saved history
  loadHistory();

  // Welcome message
  repl.writeln(ansiRGB(100, 255, 100) + ansiBold() + '=== Noita Console v2.0 ===' + ansiReset());
  repl.writeln(ansiRGB(180, 180, 180) + 'Connecting to ws://localhost:9777...' + ansiReset());
  repl.writeln('');

  // Handle window resize
  window.addEventListener('resize', function() {
    if (fit && repl._initialized) {
      try { fit.fit(); } catch(e) {}
    }
  });
}
