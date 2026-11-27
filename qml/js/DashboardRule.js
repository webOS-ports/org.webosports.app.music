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

.pragma library

/*
 * Whether the dashboard is up. As in the legacy Music app (2.2.4 and 3.0.5)
 * pausing leaves it there with a Play button; it is the only way back to the
 * music with the card closed.
 *
 * state: hasQueue, playing, cardActive (the card in front), cardSeen (it has
 * been in front), exhibition (the exhibition window is open), dismissed
 * (swiped away, or the card closed on paused music).
 *
 * cardSeen: a restored queue exists before the card first comes to the
 * front, and paused music must not put up a dashboard during the launch.
 */
function wanted(state) {
    if (!state.hasQueue || state.cardActive || state.exhibition || state.dismissed)
        return false;
    return state.playing || state.cardSeen;
}

/*
 * Whether the card is in front, from the state the card shell gives its
 * window (luna-next-cardshell publishes it: maximized or fullscreen on the
 * stage, minimized in the card view or behind another card) rather than from
 * the focus: tapping another app's dashboard, the volume bubble or anything
 * else of the shell's takes the focus from a card still on the screen, and
 * touching our own dashboard gives it to the application while the card
 * stays away. Only a window the shell gives no state (on the desktop, an
 * older shell) goes by the focus.
 *
 * state: maximized (maximized or fullscreen), away (minimized or hidden),
 * focused (the card window has the focus).
 */
function cardInFront(state) {
    if (state.maximized)
        return true;
    if (state.away)
        return false;
    return state.focused;
}
