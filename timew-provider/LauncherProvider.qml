import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null
    property var launcher: null
    property string name: tr("provider-name")

    function tr(key, args) {
        return pluginApi?.tr(key, args) ?? key;
    }

    // Command-mode only: this provider answers ">tw", never the plain search.
    property bool handleSearch: false
    property string supportedLayouts: "list"

    // Live status, refreshed from `timew get dom.active.json`.
    property bool active: false
    property var activeTags: []
    property string activeStart: ""

    // timew honours $TIMEWARRIORDB from the environment; we deliberately do not
    // set it here so this stays a generic, shareable plugin. Noctalia must be
    // launched with TIMEWARRIORDB in its environment for a relocated database.
    Process {
        id: statusProc
        command: ["timew", "get", "dom.active.json"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: (exitCode) => root.parseStatus(exitCode)
    }

    // Reusable process for the mutating actions (start/stop/continue/cancel).
    // Using a Process rather than execDetached lets us surface failures and
    // refresh the status line once the command completes.
    Process {
        id: actionProc
        property string label: ""
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                const err = actionProc.stderr.text.trim() || root.tr("error.command-failed");
                Logger.e("TimewProvider", actionProc.label, "failed:", err);
                ToastService.showError("timew: " + err);
            } else {
                ToastService.showNotice(actionProc.label);
            }
            root.fetchStatus();
        }
    }

    // Tick once a second while the launcher is open and tracking is active, so
    // the elapsed time in the status line counts up live. Self-stops when the
    // launcher closes or tracking ends.
    Timer {
        id: tickTimer
        interval: 1000
        repeat: true
        running: false
        onTriggered: {
            if (root.active && launcher && launcher.activeProvider === root) {
                launcher.updateResults();
            } else {
                tickTimer.running = false;
            }
        }
    }

    function init() {
        Logger.i("TimewProvider", "init");
        fetchStatus();
    }

    function onOpened() {
        fetchStatus();
        tickTimer.running = true;
    }

    function onClosed() {
        tickTimer.running = false;
    }

    function fetchStatus() {
        if (statusProc.running) return;
        statusProc.running = true;
    }

    function parseStatus(exitCode) {
        const out = statusProc.stdout.text.trim();
        if (exitCode !== 0 || out.length === 0) {
            active = false;
            activeTags = [];
            activeStart = "";
        } else {
            try {
                const obj = JSON.parse(out);
                active = true;
                activeTags = obj.tags || [];
                activeStart = obj.start || "";
            } catch (e) {
                Logger.e("TimewProvider", "failed to parse dom.active.json:", out);
                active = false;
                activeTags = [];
                activeStart = "";
            }
        }
        if (launcher && launcher.activeProvider === root) launcher.updateResults();
    }

    function runTimew(args, label) {
        if (actionProc.running) {
            Logger.w("TimewProvider", "action already running, ignoring");
            return;
        }
        actionProc.label = label;
        actionProc.command = ["timew"].concat(args);
        actionProc.running = true;
    }

    // "20260630T130321Z" (compact UTC) -> Date, or null if unparseable.
    function parseTimewTs(s) {
        if (!s || s.length < 16) return null;
        const iso = s.slice(0, 4) + "-" + s.slice(4, 6) + "-" + s.slice(6, 8)
                  + "T" + s.slice(9, 11) + ":" + s.slice(11, 13) + ":" + s.slice(13, 15) + "Z";
        const d = new Date(iso);
        return isNaN(d.getTime()) ? null : d;
    }

    function fmtDuration(ms) {
        if (ms < 0) ms = 0;
        let secs = Math.floor(ms / 1000);
        const h = Math.floor(secs / 3600);
        secs -= h * 3600;
        const m = Math.floor(secs / 60);
        secs -= m * 60;
        const pad = (n) => (n < 10 ? "0" : "") + n;
        return h + ":" + pad(m) + ":" + pad(secs);
    }

    function handleCommand(searchText) {
        return searchText.startsWith(">tw");
    }

    function commands() {
        return [{
            name: ">tw",
            description: tr("command-description"),
            icon: "clock",
            isTablerIcon: true,
            isImage: false,
            onActivate: function() {
                launcher.setSearchText(">tw ");
            }
        }];
    }

    // Shell-like tokenizer so multi-word tags can be quoted, mirroring the
    // `timew` CLI:  GenInfra 'Set up time tracking'  ->  two tags. Single and
    // double quotes group; quote characters are stripped (not passed to timew,
    // where a stray quote in a tag trips its encode/decode roundtrip check).
    function shellSplit(s) {
        const tokens = [];
        let cur = "";
        let started = false;
        let inSingle = false;
        let inDouble = false;
        for (let i = 0; i < s.length; i++) {
            const c = s[i];
            if (inSingle) {
                if (c === "'") inSingle = false; else cur += c;
            } else if (inDouble) {
                if (c === '"') inDouble = false; else cur += c;
            } else if (c === "'") {
                inSingle = true; started = true;
            } else if (c === '"') {
                inDouble = true; started = true;
            } else if (c === " " || c === "\t") {
                if (started) { tokens.push(cur); cur = ""; started = false; }
            } else {
                cur += c; started = true;
            }
        }
        if (started) tokens.push(cur);
        return tokens;
    }

    function statusEntry() {
        if (active) {
            const start = parseTimewTs(activeStart);
            const elapsed = start ? fmtDuration(new Date().getTime() - start.getTime()) : "";
            const tagStr = activeTags.join(" ");
            return {
                name: tr("status.tracking-name"),
                description: (tagStr ? tagStr + " · " : "") + elapsed,
                icon: "clock",
                isTablerIcon: true,
                onActivate: function() { fetchStatus(); }
            };
        }
        return {
            name: tr("status.idle-name"),
            description: tr("status.idle-description"),
            icon: "clock",
            isTablerIcon: true,
            onActivate: function() { fetchStatus(); }
        };
    }

    function actionEntry(name, description, icon, args, label) {
        return {
            name: name,
            description: description,
            icon: icon,
            isTablerIcon: true,
            onActivate: function() {
                runTimew(args, label);
                launcher.close();
            }
        };
    }

    function getResults(searchText) {
        const trimmed = searchText.trim();
        if (!trimmed.startsWith(">tw")) return [];
        const query = trimmed.slice(">tw".length).trim();

        // Parse the query like a timew command line. A leading verb is honoured
        // (so ">tw start <tags>" mirrors the CLI); otherwise the tokens are
        // treated as tags for a start.
        const tokens = shellSplit(query);
        const verbs = ["start", "stop", "cancel", "continue"];
        let verb = "";
        let tags = tokens;
        if (tokens.length > 0 && verbs.indexOf(tokens[0].toLowerCase()) !== -1) {
            verb = tokens[0].toLowerCase();
            tags = tokens.slice(1);
        }

        // The action being composed goes FIRST so it is the default selection —
        // typing tags then pressing Enter starts tracking immediately. The
        // status line follows beneath it.
        const out = [];
        if (verb === "stop") {
            out.push(actionEntry(tr("actions.stop-name"), tr("actions.stop-description"),
                                 "player-stop", ["stop"], tr("toast.stopped")));
        } else if (verb === "cancel") {
            out.push(actionEntry(tr("actions.cancel-name"), tr("actions.cancel-description"),
                                 "circle-x", ["cancel"], tr("toast.canceled")));
        } else if (verb === "continue") {
            out.push(actionEntry(tr("actions.continue-name"), tr("actions.continue-description"),
                                 "player-track-next", ["continue"], tr("toast.continued")));
        } else if (tags.length > 0) {
            // "start" verb, or bare tags. timew stops any current interval first,
            // so this doubles as "switch task".
            out.push(actionEntry(tr("actions.start-name", { tags: tags.join(" · ") }),
                                 tr("actions.start-description"),
                                 "player-play", ["start"].concat(tags), tr("toast.started")));
        }

        out.push(statusEntry());

        // Nothing composed yet: offer the obvious next action below the status.
        if (out.length === 1) {
            if (active) {
                out.push(actionEntry(tr("actions.stop-name"), tr("actions.stop-description"),
                                     "player-stop", ["stop"], tr("toast.stopped")));
                out.push(actionEntry(tr("actions.cancel-name"), tr("actions.cancel-description"),
                                     "circle-x", ["cancel"], tr("toast.canceled")));
            } else {
                out.push(actionEntry(tr("actions.continue-name"), tr("actions.continue-description"),
                                     "player-track-next", ["continue"], tr("toast.continued")));
            }
        }

        return out;
    }
}
