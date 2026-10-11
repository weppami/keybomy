# Keybomy

Fun keyboard stats in your Omarchy bar. It is a port of [Shakespeare](https://github.com/andreasaez/shakespeare), a macOS menu bar app, to an Omarchy shell plugin. It counts key presses, never what you type, and never touches the network.

- **Today and the last 14 days.** The bar shows today's count; the panel opens on today's number. Hover any bar for that day's count.
- **A streak that means typing.** Days with 50+ keys.
- **Honest typing speed.** Best sustained WPM over a full minute, letters and space only. Shortcuts (Ctrl, Alt or Super held) don't count toward it, and closing windows (Super+W, Super+Q) isn't counted at all.
- **Fun facts.** Your busiest hour, how far your keys have travelled, how many *Hamlets* you've typed.
- **Badges.** Ten literary milestones per month, from *Couplet* to *Complete Works*. Progress resets on the 1st; your collection stays.

## How it works

Two parts:

| Part | What it does |
| --- | --- |
| `keybomyd` (`daemon/keybomyd.py`) | A system service that reads key-down events from every keyboard under `/dev/input`, reduces each one at once to *letter*, *space* or *other*, and keeps only per-day counters. Python standard library only. |
| The plugin (`BarWidget.qml`, `Panel.qml`, `StatsView.qml`, `Stats.js`) | Reads the counters and draws the bar label and the panel. All stats, badges and fun facts are derived from the counters; nothing extra is stored. |

### Privacy and permissions

Wayland deliberately has no API for listening to keys globally. The only way to count presses is to read `/dev/input`, which is normally limited to root and the `input` group. Adding yourself to `input` would let *every* program you run read all keyboard input, so keybomy doesn't do that:

- The service is started by systemd, runs **as you** (so its files are yours), and only that process gets the `input` group (`SupplementaryGroups=input`).
- It marks itself non-dumpable, so your other processes can't borrow its open devices through `/proc` or ptrace.
- The daemon is installed root-owned at `/usr/local/lib/keybomy/keybomyd.py`, so your own processes can't rewrite the code that has keyboard access.
- systemd sandboxing: no network (`PrivateNetwork`, `IPAddressDeny=any`), read-only system and home except the data folder, read-only access to input devices only, no capabilities.
- Key codes are never stored or logged, and neither is their order. The stored file holds per-day totals, per-hour totals and the day's best WPM.

Data lives in `~/.local/share/keybomy/` (folder `0700`, files `0600`):

- `stats.json`: every day's counters, in the same schema as Shakespeare's `stats.json`. It is saved once a minute and when the service stops.
- `live.json`: today's counters and daemon status, refreshed every couple of seconds while you type.

## Install

```sh
cd ~/Work/keybomy
./install.sh
omarchy bar put keybomy --section right
```

`install.sh` links this folder into `~/.config/omarchy/plugins/keybomy`, copies the daemon to `/usr/local/lib/keybomy/`, installs `/etc/systemd/system/keybomyd.service` and starts it. It asks for sudo.

Check it's counting: `systemctl status keybomyd`, or open the panel's **Data** tab.

### Update

- **QML/JS changes** apply when the shell reloads plugins (`omarchy-shell shell rescanPlugins`, or `omarchy restart shell` if a change doesn't show).
- **Daemon changes** need `./install.sh` again, because the service runs the root-owned copy, not this folder.

## Settings

In `~/.config/omarchy/shell.json`, on the widget entry:

```json
{ "id": "keybomy", "icon": "󰌌", "compact": true }
```

- `icon`: shown before the count. Set it to `""` to show the number alone.
- `compact`: `12k` instead of `12,431`.

The panel keys are Left/Right or `1` `2` `3` to switch tabs, Esc to close, and Tab to move to the next bar panel. You can also summon it with `omarchy-shell shell summon keybomy`.

## Uninstall

```sh
omarchy plugin disable keybomy   # takes it off the bar
./install.sh uninstall           # stops and removes the service and plugin link
rm -rf ~/.local/share/keybomy    # erases your stats
```
 To erase your numbers but keep counting, use **Data → Delete all data** in the panel.

## Differences from Shakespeare

- Key counting comes from a sandboxed system service instead of a macOS event tap and the Input Monitoring permission.
- Letters are matched by key position on a QWERTY layout, as in the original. Ctrl, left Alt and Super make a press a shortcut; AltGr doesn't, since it types characters on many layouts.
- Not ported yet: the share-card studio (colourways and PNG export), the optional "top apps" tracking, and the menu colour themes. The panel follows your Omarchy theme.

## Credits

The stats model, badges, fun facts and copy come from [Shakespeare](https://github.com/andreasaez/shakespeare) (MIT). Badge word counts and landmark heights are approximate, from commonly cited figures.
