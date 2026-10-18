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

/*
 * com.palm.db for the stores: the calls with their JSON done, replies as
 * objects, and find() that follows db8's pages (at most 500 results each)
 * to the end. Needs "database.operation".
 */
QtObject {
    id: db

    property string clientName: "org.webosports.app.music"

    property LunaService _service: LunaService {
        name: db.clientName
    }

    function _reply(message) {
        try {
            return JSON.parse(message.payload);
        } catch (e) {
            return { returnValue: false, errorText: "Unreadable reply: " + message.payload };
        }
    }

    function call(method, params, ok, fail) {
        _service.call("luna://com.palm.db/" + method, JSON.stringify(params), function(message) {
            var r = db._reply(message);
            if (r.returnValue === false) {
                if (fail)
                    fail(r.errorText || ("db8 " + method + " failed"), r.errorCode);
            } else if (ok) {
                ok(r);
            }
        }, function(error) {
            if (fail)
                fail(String(error));
        });
    }

    /* Every result of query, page after page; ok(results). */
    function findAll(query, ok, fail) {
        var all = [];
        function page(key) {
            var q = Object.assign({}, query);
            q.limit = q.limit || 500;
            if (key)
                q.page = key;
            db.call("find", { query: q }, function(r) {
                all = all.concat(r.results || []);
                if (r.next && (r.results || []).length > 0)
                    page(r.next);
                else
                    ok(all);
            }, fail);
        }
        page(null);
    }

    /*
     * Calls onChange once when anything in kind changes (db8 "watch": a
     * find that answers again, with "fired", when its results would
     * differ). Returns the call, to cancel.
     */
    function watch(kind, onChange) {
        var fired = false;
        return _service.subscribe("luna://com.palm.db/find",
                                  JSON.stringify({ query: { from: kind, limit: 1 }, watch: true }),
                                  function(message) {
                                      var r = db._reply(message);
                                      if (r.fired && !fired) {
                                          fired = true;
                                          onChange();
                                      }
                                  }, function() {});
    }

    function put(objects, ok, fail) { call("put", { objects: objects }, ok, fail); }
    function merge(objects, ok, fail) { call("merge", { objects: objects }, ok, fail); }
    function del(ids, ok, fail) { call("del", { ids: ids }, ok, fail); }
    function putKind(kind, ok, fail) { call("putKind", kind, ok, fail); }
}
