$(function(){
  initCodeMirror();
  initConnection();
});

var codeWindow = null;
var connection = null;
var connected = false;
var repl = null;
var lineWindow = null;
var fit = null;

var commandHistory = [];

function ansiRGB(r, g, b) {
  return `\x1b[38;2;${r};${g};${b}m`
}

function ansiBgRGB(r, g, b) {
  return `\x1b[48;2;${r};${g};${b}m`
}

function ansiReset() {
  return '\x1b[0m'
}


function getToken() {
  var urlParams = new URLSearchParams(window.location.search);
  return urlParams.get('token');
}

function initConnection(url) {
  if(!url) {
      url = "ws://localhost:9777"
  }
  console.log("Connecting to url " + url);

  connection = new WebSocket(url);
  connection.addEventListener('open', function (event) {
    console.log('Connected: ' + url);
    connected = true;
    connection.send('AUTH "' + getToken() + '"');
    replPrint("SYS> WS connected.");
  });

  connection.addEventListener('close', function (event) {
    replPrint("SYS> WS closed.");
  });

  connection.addEventListener('message', function (event) {
    replPrint(event.data);
  });
}

function remoteEval(code) {
  if(code[0] === '!') {
    let parts = code.slice(1).split(" ");
    if(parts[0] === "connect") {
      initConnection(parts[1]);
    } else {
      replPrint("Unknown local command: " + parts[0]);
    }
  } else if(connected) {
    connection.send(code);
  }
}

function longestSharedPrefix(a, b) {
  let nchars = Math.min(a.length, b.length);
  let prefixLength = 0;
  for(prefixLength = 0; prefixLength < nchars; ++prefixLength) {
    if(a[prefixLength] != b[prefixLength]) {
      break;
    }
  }
  return a.slice(0, prefixLength);
}

function longestSetPrefix(opts) {
  if(opts.length == 0) {
    return ""
  }
  let curPrefix = opts[0];
  for(let idx = 1; idx < opts.length; ++idx) {
    curPrefix = longestSharedPrefix(curPrefix, opts[idx]);
  }
  return curPrefix;
}

function replPrint(message) {
  message = message.replace(/\n/g, "\r\n");
  if(message.indexOf("ERR>") == 0) {
    message = ansiRGB(200, 0, 0) + message + ansiReset();
  } else if(message.indexOf("RES>") == 0) {
    message = ansiRGB(100, 100, 255) + message + ansiReset();
  } else if(message.indexOf("EVAL>") == 0) {
    message = ansiRGB(100, 255, 100) + message + ansiReset();
  } else if(message.indexOf("HELP>") == 0) {
    message = ansiRGB(200, 255, 200) + message + ansiReset();
  } else if(message.indexOf("GAME>") == 0) {
    message = ansiRGB(200, 200, 200) + message + ansiReset();
  } else if(message.indexOf("COM>") == 0) {
    // 查看获得了多少条补全建议
    console.log("Got completion?");
    let parts = message.slice(4).split(" ");
    let prefix = parts[0];
    let opts = parts[1].split(",");
    if(opts.length == 1 && opts[0] != "") {
      // 填入此补全项
      lineWindow.setValue(prefix + opts[0]);
      lineWindow.setCursor(lineWindow.lineCount(), 0);
    } else if(opts.length > 1) {
      let completion = longestSetPrefix(opts);
      lineWindow.setValue(prefix + completion);
      lineWindow.setCursor(lineWindow.lineCount(), 0);
    }
    message = ansiRGB(150, 150, 150) + message + ansiReset();
  }
  repl.writeln(message);
}

function initCodeMirror() {
  codeWindow = CodeMirror.fromTextArea(document.getElementById("code"), {
    value: "-- Put multiline Lua stuff here\n",
    mode:  "lua",
    theme:  "dracula",
    lineNumbers: true,
    tabSize: 2
  });

  codeWindow.setOption("extraKeys", {
    "Shift-Enter": function(cm) {
      remoteEval(cm.getValue());
      replPrint("EVAL> [buffer]");
    },
    "Tab": function(cm) {
      cm.execCommand("insertSoftTab");
    }
  });

  lineWindow = CodeMirror.fromTextArea(document.getElementById("replinput"), {
    value: "",
    mode:  "lua",
    theme:  "dracula"
  });

  lineWindow.setOption("extraKeys", {
    "Enter": function(cm) {
      let val = cm.getValue();
      if(val == "") {
        return;
      }
      if(val.slice(-1) == "?") {
        val = 'help("' + val.slice(0,-1) + '")'
      }
      remoteEval(val);
      if(commandHistory.indexOf(val) < 0) {
        commandHistory.push(val);
      }
      replPrint("EVAL> " + val);
      cm.setValue("");
    },
    "Tab": function(cm) {
      console.log("TAB");
      const val = cm.getValue().trim();
      if(val == "") {
        return;
      }
      // 注意：[=[ 某字符串 ]=] 是 Lua 的一种特殊字符串字面量，
      // 允许在其中嵌套其他字符串字面量，包括更常见的 [[ ]] 配对形式
      remoteEval(`complete([=[${val}]=])`);
    },
    "Up": function(cm) {
      let hpos = commandHistory.indexOf(cm.getValue());
      if(hpos > 0) {
        cm.setValue(commandHistory[hpos-1]);
      } else if(hpos == 0) {
        // 什么都不做
      } else {
        cm.setValue(commandHistory[commandHistory.length-1]);
      }
    },
    "Down": function(cm) {
      let hpos = commandHistory.indexOf(cm.getValue());
      if(hpos >= 0 && hpos < commandHistory.length - 1) {
        cm.setValue(commandHistory[hpos+1]);
      }
    }
  });

  repl = new Terminal({
    theme: {
      background: '#111'
    }
  });
  fit = new FitAddon.FitAddon();
  repl.loadAddon(fit);
  repl.open(document.getElementById("repl"));
  repl._initialized = true;

  fit.fit();

  repl.writeln('Noita console');
  repl.writeln('（注意：此面板仅用于输出）');
  repl.writeln('');
}
