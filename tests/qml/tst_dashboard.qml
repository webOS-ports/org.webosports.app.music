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
import QtTest

import "../../qml/js/DashboardRule.js" as DashboardRule

/* When the dashboard is up (qml/js/DashboardRule.js). */
TestCase {
    name: "DashboardRule"

    function state(changes) {
        var s = { hasQueue: true, playing: true, cardActive: false, cardSeen: true,
                  exhibition: false, dismissed: false };
        for (var k in changes)
            s[k] = changes[k];
        return s;
    }

    function test_playing_away() {
        verify(DashboardRule.wanted(state({})));
    }

    // The point of the rule: as the legacy app, pausing keeps it.
    function test_paused_stays() {
        verify(DashboardRule.wanted(state({ playing: false })));
    }

    function test_launch_with_restored_queue() {
        verify(!DashboardRule.wanted(state({ playing: false, cardSeen: false })));
        // Started without the card first: a launch action.
        verify(DashboardRule.wanted(state({ playing: true, cardSeen: false })));
    }

    function test_nothing_to_show() {
        verify(!DashboardRule.wanted(state({ hasQueue: false })));
        verify(!DashboardRule.wanted(state({ hasQueue: false, playing: false })));
    }

    function test_card_in_front() {
        verify(!DashboardRule.wanted(state({ cardActive: true })));
    }

    function test_exhibition() {
        verify(!DashboardRule.wanted(state({ exhibition: true })));
    }

    function test_dismissed() {
        verify(!DashboardRule.wanted(state({ dismissed: true })));
        verify(!DashboardRule.wanted(state({ dismissed: true, playing: false })));
    }
}
