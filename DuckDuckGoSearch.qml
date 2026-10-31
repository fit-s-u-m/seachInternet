import Quickshell.Io
import QtQuick
import Quickshell
import qs.Common
import qs.Services

QtObject {
    id: root

    property var pluginService: null
    property string pluginId: "dankDuckDuckGoSearch"
    property string trigger: "ddg "

    // Instant Answer preview state
    property string currentQuery: ""      // latest query seen by getItems
    property string previewQuery: ""      // query the stored preview belongs to
    property var preview: null            // { text, source } or null
    property int _requestId: 0
    property var _activeXhr: null

    signal itemsChanged

    property string netStatus: "no request yet"
    property int _calls: 0
    property int _fetches: 0

    Component.onCompleted: {
        if (pluginService) {
            trigger = pluginService.loadPluginData(pluginId, "trigger", "ddg ");
        }
    }

    onTriggerChanged: {
        if (!pluginService)
            return;
        pluginService.savePluginData(pluginId, "trigger", trigger);
    }

    /**
     * Request a launcher update from the DMS plugin service.
     */
    function requestUpdate() {
        if (!pluginService || !pluginId)
            return;
        if (typeof pluginService.requestLauncherUpdate === "function")
            pluginService.requestLauncherUpdate(pluginId);
    }

    // ---------- helpers ----------

    // A bang is "!" followed by non-space, at the start or after whitespace.
    function hasBang(q) {
        return /(^|\s)!\S/.test(q);
    }

    function searchUrl(q) {
        // Raw query goes to ?q= untouched (only URL-encoded) so DDG resolves bangs server-side.
        return "https://duckduckgo.com/?q=" + encodeURIComponent(q);
    }

    function truncate(s, max) {
        s = (s || "").replace(/\s+/g, " ").trim();
        if (s.length <= max)
            return s;
        return s.substring(0, max - 1).trim() + "…";
    }

    // ---------- Preview fetching (debounced) ----------
    // Order: Wikipedia (typo-tolerant, short summary) -> DuckDuckGo Instant Answer fallback.

    property Timer debounceTimer: Timer {
        interval: 280
        repeat: false
        onTriggered: root.fetchPreview(root.currentQuery)
    }

    function cancelActive() {
        _requestId++;
        if (_activeXhr) {
            try {
                _activeXhr.abort();
            } catch (e) {}
            _activeXhr = null;
        }
    }

    function setPreview(q, text, source) {
        preview = {
            text: truncate(text, 120),
            source: source
        };
        previewQuery = q;
        requestUpdate();
    }

    /**
     * GET a JSON url. Calls onData(obj) on success, onFail() on any failure.
     * Stale responses (query changed / request cancelled) are dropped silently.
     */
    function getJson(url, q, myId, onData, onFail) {
        const xhr = new XMLHttpRequest();
        _activeXhr = xhr;
        xhr.timeout = 3000;

        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (myId !== root._requestId || q !== root.currentQuery) {
                root.netStatus = "http " + xhr.status + " DROPPED stale (myId=" + myId + " reqId=" + root._requestId + ")";
                root.requestUpdate();
                return;
            }
            root.netStatus = "http " + xhr.status + " ok-fresh";
            root._activeXhr = null;

            if (xhr.status !== 200) {
                root.netStatus = "http " + xhr.status + " FAILED (not 200)";
                root.requestUpdate();
                onFail();
                return;
            }
            let data = null;
            try {
                data = JSON.parse(xhr.responseText);
            } catch (e) {
                root.netStatus = "http 200 but JSON parse FAILED";
                root.requestUpdate();
                onFail();
                return;
            }
            onData(data);
        };

        xhr.open("GET", url);
        xhr.send();
    }

    function fetchPreview(q) {
        if (!q || hasBang(q))
            return;

        cancelActive();
        _fetches++;
        netStatus = "requesting...";
        fetchWikipedia(q, _requestId);
    }

    function fetchWikipedia(q, myId) {
        const url = "https://en.wikipedia.org/w/api.php?action=query&generator=search"
            + "&gsrsearch=" + encodeURIComponent(q)
            + "&gsrenablerewrites=1&gsrlimit=1&prop=extracts&exintro=1&explaintext=1"
            + "&exsentences=2&redirects=1&format=json";

        getJson(url, q, myId, function (data) {
            let text = "";
            let title = "";
            if (data && data.query && data.query.pages) {
                for (const k in data.query.pages) {
                    const pg = data.query.pages[k];
                    if (pg && typeof pg.extract === "string" && pg.extract.trim() !== "") {
                        text = pg.extract;
                        title = pg.title || "";
                        break;
                    }
                }
            }
            if (text === "") {
                root.netStatus = "wikipedia: no extract, trying DDG";
                root.fetchDuckDuckGo(q, myId);
                return;
            }
            root.netStatus = "wikipedia: found " + title;
            root.setPreview(q, text, title ? `Wikipedia  •  ${title}` : "Wikipedia");
        }, function () {
            root.fetchDuckDuckGo(q, myId);
        });
    }

    function fetchDuckDuckGo(q, myId) {
        const url = "https://api.duckduckgo.com/?q=" + encodeURIComponent(q)
            + "&format=json&no_html=1&t=dms-ddg";

        getJson(url, q, myId, function (data) {
            let text = "";
            let source = "";

            if (typeof data.Answer === "string" && data.Answer.trim() !== "") {
                text = data.Answer;
                source = data.AnswerType || data.AbstractSource || "";
            } else if (data.AbstractText && data.AbstractText.trim() !== "") {
                text = data.AbstractText;
                source = data.AbstractSource || "";
            } else if (data.Definition && data.Definition.trim() !== "") {
                text = data.Definition;
                source = data.DefinitionSource || data.AbstractSource || "";
            }

            // Ambiguous queries: first related topic
            if (text === "" && Array.isArray(data.RelatedTopics)) {
                for (let i = 0; i < data.RelatedTopics.length && text === ""; i++) {
                    const t = data.RelatedTopics[i];
                    if (t && typeof t.Text === "string" && t.Text.trim() !== "") {
                        text = t.Text;
                    } else if (t && Array.isArray(t.Topics)) {
                        for (let j = 0; j < t.Topics.length; j++) {
                            if (t.Topics[j] && t.Topics[j].Text) {
                                text = t.Topics[j].Text;
                                break;
                            }
                        }
                    }
                }
                if (text !== "")
                    source = "DuckDuckGo";
            }

            if (text === "")
                return;
            root.setPreview(q, text, source || "DuckDuckGo");
        }, function () {});
    }

    // ---------- launcher API ----------

    /**
     * Get searchable items based on the query string.
     */
    function getItems(query) {
        const rawQuery = query || "";
        let q = rawQuery.trim();

        // Defensive: some DMS paths may leave the trigger word on the query
        const trig = (trigger || "").trim().toLowerCase();
        if (trig !== "" && q.toLowerCase().startsWith(trig + " "))
            q = q.substring(trig.length).trim();
        else if (trig !== "" && q.toLowerCase() === trig)
            q = "";
        _calls++;

        if (q === "") {
            debounceTimer.stop();
            cancelActive();
            currentQuery = "";
            preview = null;
            previewQuery = "";
            return [];
        }

        // New query: drop stale preview, restart debounce. Repeated calls with the
        // same query (e.g. from requestUpdate) must not restart anything.
        if (q !== currentQuery) {
            currentQuery = q;
            if (previewQuery !== q)
                preview = null;
            cancelActive();
            if (hasBang(q))
                debounceTimer.stop();
            else
                debounceTimer.restart();
        }

        const items = [];
        const bang = hasBang(q);

        if (!bang && preview && previewQuery === q) {
            const hint = "Press Enter for more results";
            items.push({
                id: "ddg-preview",
                name: preview.text,
                icon: "web-browser",
                // The query is included in the subtitle on purpose: DMS filters plugin
                // results against the typed text, and a Wikipedia summary rarely contains it.
                comment: preview.source ? `${q}  •  ${preview.source}  •  ${hint}` : `${q}  •  ${hint}`,
                keywords: [q],
                action: "open:" + q,
                categories: ["DuckDuckGo"],
                ddgQuery: q,
                score: 1100,
                priority: 1100,
                weight: 1100,
                relevance: 1100
            });
        }

        items.push({
            id: "ddg-search",
            name: bang ? `Open ${q} in browser` : `Search DuckDuckGo for '${q}'`,
            icon: "web-browser",
            comment: bang ? "DuckDuckGo bang  •  default browser" : "DuckDuckGo  •  default browser",
            action: "open:" + q,
            categories: ["DuckDuckGo"],
            ddgQuery: q,
            score: 1000,
            priority: 1000,
            weight: 1000,
            relevance: 1000
        });

        return items;
    }

    /**
     * Execute an action when the user selects an item.
     */
    function executeItem(item) {
        if (!item || !item.action)
            return;

        if (!item.action.startsWith("open:"))
            return;

        const q = item.ddgQuery || item.action.substring(5);
        if (!q || q.trim() === "")
            return;

        openInBrowser(searchUrl(q));
    }

    property Process openProcess: Process {
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    console.error("[DuckDuckGo Plugin] Failed to open browser:", text);
            }
        }
    }

    function openInBrowser(url) {
        openProcess.command = ["xdg-open", url];
        openProcess.running = true;
    }
}
