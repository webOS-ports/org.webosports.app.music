/*
 * (c) 2026 Herman van Hazendonk <github.com@herrie.org>
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 3, as published
 * by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranties of
 * MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
 * PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick

import LuneOS.Service 1.0

import "js/Streaming.js" as Streaming

/*
 * The streaming services: the music streaming service (the
 * spotify-webos-service daemon, plain HTTP on 127.0.0.1:8730) searches them
 * and resolves their tracks to URLs this app plays itself; Spotify plays
 * through the daemon's librespot (SpotifyEngine).
 *
 * A service counts as signed in when the daemon has it and the user has
 * its account in Accounts (a Synergy account of template
 * org.webosports.app.music.<id>) - the daemon keeps a service's
 * credentials after its account is removed, so its list alone is not
 * enough. YouTube needs no account.
 */
Item {
    id: store

    property string baseUrl: "http://127.0.0.1:8730"
    property string clientName: "org.webosports.app.music"

    // [{ id, name }] of the signed-in services, by name.
    property var providers: []
    // "unknown", "ready" or "unavailable" (no daemon).
    property string status: "unknown"
    readonly property bool available: status === "ready" && providers.length > 0

    // function(method, url, body, done(httpStatus, jsonOrNull)): the HTTP
    // calls, replaceable by the tests.
    property var transport: _xhr

    // The account template ids present, null until Accounts answered (or
    // when it cannot be asked: then every service the daemon has counts).
    property var _accountIds: null
    property var _daemonProviders: null

    function _xhr(method, url, body, done) {
        var req = new XMLHttpRequest();
        req.onreadystatechange = function() {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            var data = null;
            try {
                data = req.responseText ? JSON.parse(req.responseText) : null;
            } catch (e) {
                data = null;
            }
            done(req.status, data);
        };
        req.open(method, url);
        if (body !== undefined && body !== null) {
            req.setRequestHeader("Content-Type", "application/json");
            req.send(JSON.stringify(body));
        } else {
            req.send();
        }
    }

    LunaService {
        id: accounts
        name: store.clientName
    }

    /* Asks the daemon and Accounts again (the app coming to the front, a
     * new account). */
    function refresh() {
        transport("GET", baseUrl + "/providers", null, function(code, data) {
            if (code !== 200 || !data || !Array.isArray(data.providers)) {
                store._daemonProviders = null;
                store.status = "unavailable";
                store.providers = [];
                return;
            }
            store._daemonProviders = data.providers;
            store.status = "ready";
            store._update();
        });
        // Needs "accountsservice.operation".
        accounts.call("luna://com.palm.service.accounts/listAccounts", "{}", function(message) {
            var r = {};
            try {
                r = JSON.parse(message.payload);
            } catch (e) {
                r = {};
            }
            if (r.returnValue === false || !Array.isArray(r.results)) {
                store._accountIds = null;
            } else {
                store._accountIds = r.results.filter(function(a) { return !a.beingDeleted; })
                                             .map(function(a) { return a.templateId; });
            }
            store._update();
        }, function() {
            store._accountIds = null;
            store._update();
        });
    }

    function _update() {
        if (!_daemonProviders)
            return;
        providers = Streaming.signedIn(_daemonProviders, _accountIds);
    }

    function provider(id) {
        for (var i = 0; i < providers.length; i++) {
            if (providers[i].id === id)
                return providers[i];
        }
        return null;
    }

    /* done(tracks, error): a service's search, as the app's tracks. */
    function search(providerId, text, limit, done) {
        var q = String(text).trim();
        if (q === "") {
            done([], "");
            return;
        }
        transport("GET", baseUrl + "/provider/" + encodeURIComponent(providerId) + "/search?q="
                  + encodeURIComponent(q) + "&limit=" + (limit || 25), null, function(code, data) {
            if (code !== 200 || !data || !Array.isArray(data.tracks)) {
                done([], (data && data.error) ? data.error : "The service did not answer.");
                return;
            }
            done(data.tracks.map(function(t) { return Streaming.track(t, store.providerName(providerId)); }), "");
        });
    }

    function providerName(id) {
        var p = provider(id);
        return p ? p.name : Streaming.displayName(id);
    }

    /* done(url, error): what plays a streamed track. */
    function resolve(track, done) {
        var parts = Streaming.split(track.path);
        if (!parts) {
            done("", "Not a streamed track.");
            return;
        }
        transport("POST", baseUrl + "/provider/" + encodeURIComponent(parts.provider) + "/resolve",
                  { trackId: parts.id }, function(code, data) {
            if (code === 200 && data && data.url)
                done(data.url, "");
            else
                done("", (data && data.error) ? data.error : "The streaming service is not running.");
        });
    }
}
