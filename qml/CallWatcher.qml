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
import QOfono 0.2

/*
 * Tells when a phone call starts and when the last one ends, from oFono's
 * voice call manager, so the music can pause for it and carry on after.
 * Loaded through a Loader: where QOfono is missing (a tablet without a
 * modem) the player does without it.
 */
Item {
    id: watcher

    signal callStarted()
    signal callsEnded()

    property int _calls: 0

    OfonoManager {
        id: manager
    }

    OfonoVoiceCallManager {
        modemPath: manager.defaultModem ? manager.defaultModem : ""
        onCallAdded: {
            watcher._calls++;
            if (watcher._calls === 1)
                watcher.callStarted();
        }
        onCallRemoved: {
            watcher._calls = Math.max(0, watcher._calls - 1);
            if (watcher._calls === 0)
                watcher.callsEnded();
        }
    }
}
