# termcheck

Check what a shell on a remote machine can send to the terminal you're sitting
at: clipboard copies, notifications, images, links and 24-bit colour, over SSH
and mosh, and through tmux and GNU screen. Where something doesn't get through,
`termcheck` says what to change.

```sh
# on a remote server, inside tmux, in Warp
$ termcheck
Connection
  ok:    over SSH
  ok:    tmux 3.7, allow-passthrough on, set-clipboard external

Terminal
  ok:    Warp, from its answer to XTVERSION: Warp(v0.2026.05.06.15.42.stable_02)
  ok:    it answered, asked through tmux: kitty images: yes; sixel: no; kitty notifications: no; 1440x720 pixels
  note:  Warp: for notifications, turn on Settings > Features > Notifications > "Receive desktop notifications"
  ok:    TERM=tmux-256color, terminfo entry /lib/terminfo/t/tmux-256color
  ok:    your terminal's TERM, outside tmux: xterm-256color

Features
  Feature         Status Detail
  clipboard       fix    tmux ignores programs' copies (set-clipboard external)
  notifications   ok     OSC 9, OSC 777; through tmux, only from programs that wrap them
  images          ok     kitty protocol; through tmux, only from programs that wrap them
  links           fix    tmux doesn't know your terminal has them
  24-bit colour   fix    tmux doesn't know your terminal has it, and shows 256 colours

To fix
  - Add to ~/.tmux.conf:
      set -g set-clipboard on
      set -as terminal-features ',xterm-256color:hyperlinks:RGB'
    Then run 'tmux source-file ~/.tmux.conf', then detach and reattach
```

Each of these features travels as an **escape sequence**: bytes in a program's
output that your terminal acts on instead of printing. Between the program and
your terminal there may be tmux, GNU screen, SSH or mosh. Each passes some
sequences on, drops others, or needs a setting first, and your terminal has to
understand the sequence too. `termcheck` asks your terminal what it is (through
tmux and screen as well), reads tmux's and screen's settings, and checks the
terminfo entry for `$TERM`. It needs bash and coreutils, and changes nothing
itself.

- [Install](#install)
- [Usage](#usage)
- [Reading the report](#reading-the-report)
- [What gets through where](#what-gets-through-where)
- [The fixes](#the-fixes)
- [Your terminal](#your-terminal)
- [Seeing for yourself: -t](#seeing-for-yourself--t)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)
- [How it works](#how-it-works)
- [Uninstall](#uninstall)
- [Testing](#testing)
- [References](#references)

---

## Install

On the machine you SSH **into**:

```sh
git clone <repo-url> termcheck
cd termcheck
./setup.sh
```

`setup.sh`:

| Step | What it does |
| --- | --- |
| Requirements | Checks for bash 4 or later, and `stty`, `base64`, `tr`, `sed`, `grep`, `head`, `wc`, `cat` and `sleep` (coreutils, sed and grep). Reports whether `infocmp` (ncurses) is there, which `termcheck` uses to check terminfo entries |
| Install | Copies `termcheck` to `~/bin` |
| PATH | If `~/bin` isn't on `PATH`, adds it at the top of `~/.bashrc` (before any early return for non-interactive shells), or to `~/.zshenv` for zsh |

It's safe to re-run, for example after `git pull`. The line it adds is preceded
by a `# added by termcheck setup.sh` comment. Unlike tools that need tmux set
up, `setup.sh` leaves your tmux and screen configuration alone: finding out what
they need is `termcheck`'s job.

Then, in a new shell:

```sh
termcheck
```

---

## Usage

```
Usage: termcheck [-t] [-v]

Check what this shell can send to the terminal you're sitting at, over SSH
and mosh, and through tmux and GNU screen: clipboard copies (OSC 52),
notifications, images, links (OSC 8) and 24-bit colour. Says what to change
where something doesn't get through.

  -t   also send a test of each feature, to see which ones arrive. This
       copies a line of text to your clipboard. Inside tmux or screen, it
       then waits for Enter to remove the kitty image
  -v   also show your terminal's answers, as they arrived
  -h   show this help

Exit status: 0 if nothing needs changing, 1 if something does, 2 for a usage
error.
```

Run it in each place you work: outside tmux, inside tmux, inside screen. Each
has its own answers. Run it again after switching terminal, and on each new
server.

```sh
termcheck            # the report
termcheck -t         # the report, then a test of each feature
termcheck -v         # the report, with your terminal's answers byte by byte
termcheck || echo 'something to fix'
```

---

## Reading the report

The report has up to five parts.

**Connection** says how you're connected: over SSH, over mosh, or neither (a
terminal on this machine itself). Inside tmux, it looks at the tmux client
you're using, so it's right even when you started tmux in another session.
Then the multiplexer: tmux's version and the two settings that matter most, or
screen's version.

**Terminal** says which terminal you're using and how `termcheck` found out. In
order of preference: its answer to an XTVERSION query, tmux's
`#{client_termtype}` (tmux 3.3+ asks the same question when you attach),
`$LC_TERMINAL`, `$TERM_PROGRAM`, tmux's `#{client_termname}` and `$TERM`. Then
what the terminal answered: whether it takes kitty-protocol images, whether it
reports sixel, whether it answers kitty's notification query, and its size in
pixels. Then any setting to switch on in the terminal itself, and whether there
is a terminfo entry for `$TERM` on this machine.

**Features** has one row per feature:

| Status | Meaning |
| --- | --- |
| `ok` | It gets through to your terminal, and your terminal shows it. The detail may add a condition, such as "only from programs that wrap them" (see [Wrapped sequences](#wrapped-sequences)) |
| `fix` | Something on this machine stops it, and a setting would let it through. The fix is under **To fix** |
| `no` | It can't get through, or your terminal doesn't have it: for example screen and links, or mosh and images. The detail says which |
| `?` | `termcheck` can't tell: usually a terminal it doesn't know. `termcheck -t` lets you see for yourself |

**To fix** lists the changes, with the lines to add. **Notes** lists things
worth knowing that aren't wrong as such: for example that `COLORTERM` isn't
set, or, where your terminal shows no images, that X11 forwarding is on (see
[PuTTY, KiTTY and MobaXterm](#putty-kitty-and-mobaxterm)).

The exit status is 1 if there's anything under **To fix**, and 0 otherwise.

### Wrapped sequences

tmux and screen drop notification and image sequences, but both pass on a
sequence that's **wrapped** in their own envelope. tmux's is
`ESC Ptmux; ... ESC \`, which also needs `allow-passthrough` on from tmux 3.3.
screen's is a DCS string, `ESC P ... ESC \`. A program has to do the wrapping
itself, so "only from programs that wrap them" means that tools written with
tmux or screen in mind work there, and a plain `printf` of the sequence
doesn't. Clipboard copies, links and colour need no wrapping in tmux, which
handles those itself once it knows your terminal has them.

---

## What gets through where

This is what `termcheck` goes by. Each cell comes from the source code of tmux,
screen and mosh (see [References](#references)). Where tmux 3.1, tmux 3.7 or
screen 4.8 were also tested, [Testing](#testing) says so.

| Feature | Sequence | tmux | GNU screen | mosh 1.4 |
| --- | --- | --- | --- | --- |
| Clipboard copies | OSC 52 | Passes it on with `set-clipboard on` (the default, `external`, ignores copies from programs), if it knows the terminal has `clipboard` (any `TERM` matching `xterm*` does) | Drops it; passes it on wrapped | Passes it on |
| Notifications | OSC 9, OSC 777, OSC 99 | Drops them (it reads OSC 9 only as `9;4`, a progress bar); passes them on wrapped | Drops them; passes them on wrapped | Drops them |
| Images | kitty protocol, iTerm2 protocol, sixel | Drops them; passes them on wrapped. Before 3.3, can drop large ones | Passes them on wrapped, in pieces | Drops them |
| Links | OSC 8 | From 3.4, passes them on if it knows the terminal has `hyperlinks`. Before 3.4, drops them | Drops them (screen 4 and 5) | Drops them (support was added after 1.4, not yet released) |
| 24-bit colour | `ESC [38;2;R;G;Bm` | Passes it on if it knows the terminal has `RGB` (3.2+), or with `Tc` in `terminal-overrides` (before 3.2). Otherwise turns it into 256 colours | screen 5 with `truecolor on`. screen 4 has 256 colours (tested: 4.8 turned the colours into a few basic ones) | Passes it on (1.4+) |

How tmux knows what your terminal has: from its `TERM`, through the terminfo
entry and `terminal-features` (by default `xterm*:clipboard:ccolour:cstyle:focus:title`),
and from its answer to XTVERSION when you attach. tmux gives extra features to
the terminals it recognises that way: iTerm2, WezTerm, Ghostty, foot, XTerm,
mintty, rxvt-unicode and Rio. Warp isn't among them, and Warp sets `TERM` to
`xterm-256color`, so inside tmux Warp gets the clipboard but not 24-bit colour
or links until you add them. `termcheck` reads what tmux decided, from
`#{client_termfeatures}`.

SSH passes every sequence on. It doesn't pass on most environment variables,
though: `COLORTERM`, which many programs read to decide whether to use 24-bit
colour, and `TERM_PROGRAM` aren't set on the remote machine unless both ends
are set up to send them. `LC_TERMINAL`, which iTerm2 sets, often gets through,
because servers usually accept `LC_*` variables.

---

## The fixes

### tmux

```sh
set -g set-clipboard on
```

tmux's default, `external`, lets tmux set your terminal's clipboard when you
copy in tmux's copy mode, but ignores OSC 52 from programs (Neovim's
clipboard, command-line copy tools and the like). `on` passes them on too.

```sh
set -g allow-passthrough on
```

Lets programs send wrapped sequences, such as images and notifications, to
your terminal from the pane you're looking at (`all`: from any pane). It
arrived in tmux 3.3 and is off by default. Older versions pass wrapped
sequences on without it. **Caution:** passthrough lets any program in the pane
send your terminal sequences that tmux would otherwise filter, which is the
same as running that program without tmux.

```sh
set -as terminal-features ',xterm-256color:hyperlinks:RGB'
```

Tells tmux that terminals with this `TERM` have links and 24-bit colour (and
`clipboard`, if that's missing). `termcheck` uses your terminal's actual `TERM`
(tmux's `#{client_termname}`) in the line. The pattern matches every terminal
that attaches with that `TERM`, so if you also attach from one without these
features, such as Apple's Terminal.app, it gets them too. tmux works out what a
terminal has when it attaches, so after `tmux source-file ~/.tmux.conf`, detach
and reattach. `terminal-features` arrived in tmux 3.2. For older tmux,
`termcheck` suggests the older form instead:

```sh
set -as terminal-overrides ',xterm-256color:Tc'
```

`-a` appends to the list, so sourcing the file twice adds the entry twice,
which does no harm.

Where there's no `~/.tmux.conf` but there is a `$XDG_CONFIG_HOME/tmux/tmux.conf`
or `~/.config/tmux/tmux.conf`, which tmux also reads, `termcheck` names that
file instead.

If the terminfo entry for tmux's own `TERM` (its `default-terminal`, such as
`tmux-256color`) is missing, `termcheck` suggests `set -g default-terminal
screen-256color`, which nearly every system has.

### GNU screen

```sh
truecolor on
```

In `~/.screenrc`, for screen 5. It's off by default, and takes effect in new
screen sessions. screen 4 has no 24-bit colour, so the fix there is screen 5.

screen drops links whatever the version, and passes clipboard copies,
notifications and images on only when they're wrapped.

### mosh

Nothing to set. mosh redraws the screen itself and passes on only what it
understands: clipboard copies and 24-bit colour. For images and notifications,
use SSH.

### Terminfo

Programs look up `$TERM` in the terminfo database to learn how to drive your
terminal. Newer terminals' entries (kitty's `xterm-kitty`, Ghostty's
`xterm-ghostty`, foot's `foot`) are missing on many machines. Then zsh can't
edit the command line properly and screen refuses to start. `termcheck` checks
with `infocmp`, or by looking for the file where there's no `infocmp`, and
suggests copying the entry over. Run this on your own machine, in the terminal
in question. It needs no root on the remote machine:

```sh
infocmp -a xterm-kitty | ssh host tic -x -o \~/.terminfo /dev/stdin
```

ncurses keeps each entry in a directory named after the entry's first letter
(`~/.terminfo/x/xterm-kitty`) or, in some builds such as conda-forge's
current one, after that letter's hex code (`~/.terminfo/78/xterm-kitty`).
A program built against one doesn't look in the other, so a screen compiled
against Miniforge can't find an entry that the system's `tic` installed. Where
`~/.terminfo` has the only copy of the entry, in just one of the two places,
`termcheck` suggests a link:

```sh
mkdir -p ~/.terminfo/78 && ln -s ../x/xterm-kitty ~/.terminfo/78/xterm-kitty
```

Where `infocmp` can't read the entry in either place, the file itself is
damaged, or was written by a newer ncurses than this machine's (ncurses 6.1
and later use a format older ones can't read for entries with large numbers,
such as `xterm-direct`). Then `termcheck` suggests copying the entry over again
with the `tic` command above, which compiles it with this machine's ncurses.

### COLORTERM

```sh
export COLORTERM=truecolor
```

Many programs only use 24-bit colour when `COLORTERM` says they can, and SSH
doesn't pass it on. Where your terminal has 24-bit colour and `COLORTERM` isn't
set, `termcheck` notes this. Add the line to your shell's startup file on the
remote machine, but only if every terminal you connect from has 24-bit colour.
tmux 3.6 and later set it in their panes themselves.

---

## Your terminal

Some things can be asked of a terminal and some can't. For the rest,
`termcheck` goes by this table, which comes from each terminal's documentation
and, for Warp, from its source code. It hasn't been checked against the
terminals themselves:

| Terminal | Clipboard copies | Notifications | Images | Links | 24-bit colour | To switch on |
| --- | --- | --- | --- | --- | --- | --- |
| Warp | yes | OSC 9, OSC 777 | kitty | yes | yes | Notifications: Settings > Features > Notifications > "Receive desktop notifications" |
| kitty | yes | OSC 9, OSC 99 | kitty | yes | yes | |
| Ghostty | yes | OSC 9, OSC 777 | kitty | yes | yes | |
| iTerm2 | if switched on | OSC 9 | iTerm2, sixel | yes | yes | Clipboard: Settings > General > Selection > "Applications in terminal may access clipboard". Notifications: Settings > Profiles > Terminal |
| WezTerm | yes | OSC 9, OSC 777 | iTerm2, sixel | yes | yes | |
| foot | yes | OSC 777 | sixel | yes | yes | |
| Alacritty | yes | none | none | yes | yes | |
| Terminal.app | no | none | none | ? | ? | |
| GNOME Terminal and other VTE terminals | no | ? | none | yes | yes | |
| PuTTY, KiTTY, MobaXterm (recognised together, see below) | PuTTY, MobaXterm: no. KiTTY: yes | none | none | ? | yes | |

What it answers counts for more than the table: a terminal that answers the
kitty image query takes kitty images, one whose DA1 answer includes 4 has
sixel, and one that answers kitty's notification query shows OSC 99. A DA1
answer *without* 4 removes sixel from the table's list. Outside tmux and
screen, `COLORTERM=truecolor` (or `24bit`) counts as 24-bit colour.

`termcheck` recognises a terminal by name when one of its names says so. The
one exception is the PuTTY family (below), which it recognises by its DA1
answer. Windows Terminal, VS Code, mintty and others come out as unknown, and
their rows are `?` apart from what they answered. VTE terminals are recognised
only if they give their name. A `?` is the cue for
[`-t`](#seeing-for-yourself--t).

### PuTTY, KiTTY and MobaXterm

PuTTY gives no name, and neither do KiTTY and MobaXterm, whose terminals come
from PuTTY's. But all three answer DA1 as a VT102, `ESC [?6c`, which few other
terminals do, so `termcheck` recognises them by that, without telling them
apart. (The Linux console answers the same, so outside tmux and screen, with
`TERM=linux`, it doesn't.)

- **24-bit colour:** yes. PuTTY has had it since 0.71, MobaXterm since 8.3.
- **Notifications, images:** none. MobaXterm printed the sixel test as text.
- **Links:** PuTTY's wishlist marks OSC 8 as "never". MobaXterm's and KiTTY's
  support is unknown, so the row says `?`, and `-t` outside screen and tmux
  settles it.
- **Clipboard copies:** PuTTY doesn't take them, and neither did MobaXterm in
  testing, inside screen or outside it. KiTTY does. As `termcheck` can't tell
  the three apart, the row says `?`, and the detail says which do.

MobaXterm has an X server built in, and switches on X11 forwarding for SSH
sessions. Where your terminal shows no images and `$DISPLAY` is set,
`termcheck` notes that graphical programs (R's `x11()` device, ImageMagick's
`display`) open windows on your machine instead. Inside tmux and screen,
`$DISPLAY` dates from when the session started, so it may be stale.

---

## Seeing for yourself: -t

Some things can't be checked from the remote machine at all: whether a
notification actually popped up, or whether your terminal really took the
clipboard copy. `termcheck -t` sends one of each, after the report, and says
what to look for:

| Test | What it sends | What you should see |
| --- | --- | --- |
| clipboard | OSC 52 with `termcheck clipboard test` (replacing what's on your clipboard) | Paste somewhere: that text |
| notifications | OSC 9, OSC 777 and OSC 99, each with its own message | One notification for each kind your terminal shows: "OSC 9 works" and so on |
| images | A red bar in each protocol: kitty, iTerm2, sixel | A red bar after the name of each protocol your terminal shows |
| link | OSC 8 to `https://example.com/` | "termcheck link test" as a clickable link |
| colour | 40 cells shading from red to blue in 24-bit colour | One smooth band. Visible steps mean 256 colours |

The tests go through tmux and screen the way most programs send them:
clipboard copies, links and colour unwrapped (so they also test tmux's
settings), and notifications and images wrapped (inside screen, the clipboard
copy is wrapped too). A terminal that doesn't understand a sequence normally
ignores it, but one without sixel may print the sixel test as text. So where
the terminal's DA1 answer says it has no sixel, `termcheck` doesn't send that
test, and says so.

Inside tmux or screen, the kitty image doesn't go away by itself. tmux and
screen don't know it's there, so it stays where it was drawn when they scroll
or clear the screen. Warp, for one, keeps it there until it's deleted or you
leave tmux or screen. So where your terminal said it shows kitty images,
`termcheck -t` ends by waiting for Enter (or Ctrl-C), then deletes the image.
The iTerm2 protocol has no way to delete an image, so `termcheck` can't remove
that one.

---

## Limitations

- **Things that can't be asked.** No terminal reports whether it takes
  clipboard copies, shows OSC 9 or OSC 777 notifications, iTerm2 images or
  links. For those, `termcheck` goes by [the table](#your-terminal), or says
  `?`. Use `-t`.
- **The table can go out of date**, and it describes default settings. A
  terminal set up differently, or a newer version, may differ.
- **Inside GNU screen** `termcheck` can't tell how you're connected (it goes by
  `$SSH_CONNECTION`, which dates from when the screen session started), and
  `$LC_TERMINAL` and `$TERM_PROGRAM` also date from then. It doesn't read the
  version of the running screen, but of the `screen` on `PATH`, and it reads
  `truecolor` from `~/.screenrc`, not from the running session.
- **Inside mosh** your terminal can't be asked: mosh answers such questions
  itself.
- **tmux and screen inside one another** aren't checked: `termcheck` warns and
  checks the inner one.
- **A tmux further out**, such as one on your own machine that you SSH from,
  answers the questions itself, so `termcheck` can't tell which terminal you
  use, and can't read that tmux's settings. It says so, and the rows are
  mostly `?`. Run `termcheck` (and `-t`) in that tmux too.
- **Several terminals attached to one tmux session.** `termcheck` checks the
  one you used last, but all of them may answer its questions; it reads the
  first answers.
- **No `/proc`** (macOS, BSD): `termcheck` can't tell SSH from mosh, and goes by
  `$SSH_CONNECTION`.
- **tmux control mode** (iTerm2's `tmux -CC` integration) isn't supported.
- **Wrapped sequences** are reported as getting through when tmux or screen
  passes them on, but each tool has to wrap them itself. `termcheck` can't
  check your tools.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| A 2-second pause, then `it didn't answer in 2 seconds` | Your terminal answers nothing, or tmux dropped the questions (the pane isn't the one on screen) | Run it in the pane you're looking at. Otherwise the table and `-t` have to do |
| `not asked: tmux's allow-passthrough is off` | tmux 3.3+ drops wrapped sequences, the questions included | `tmux set -g allow-passthrough on`, then run it again; or go by `#{client_termtype}`, which `termcheck` uses anyway |
| Your terminal's name is right, but a feature says `fix` in tmux | tmux doesn't know your terminal has it | Add the `terminal-features` line under **To fix**, then detach and reattach |
| Still `fix` after adding the line and sourcing `~/.tmux.conf` | tmux works out what a terminal has when it attaches | Detach and reattach |
| `WARN: TERM=..., which has no terminfo entry here` | A newer terminal whose entry this machine lacks | See [Terminfo](#terminfo) |
| `ok` in the report, but nothing happens | A setting in the terminal itself (iTerm2's clipboard, Warp's notifications), or your desktop blocks the terminal's notifications | See the `note:` under **Terminal**, and [Your terminal](#your-terminal) |
| Garbage printed during `-t` | The terminal printed a sequence it doesn't understand, such as sixel from a terminal that didn't answer DA1 | Harmless; `clear` |
| `tmux 3.5a answered, not your terminal` | You run tmux on your own machine as well, or somewhere else between here and your terminal | Run `termcheck` in that tmux too. `-t` here shows what gets through both |
| `WARN: can't read tmux's settings: tmux display failed: ...` | The `tmux` on `PATH` can't talk to the running server: "protocol version mismatch" means it's another version (say a conda tmux, and the system's running the server); "error connecting" means `$TMUX` is left over from a session that has gone | Run `termcheck` with the server's tmux first on `PATH`, or restart the server with the new tmux (`tmux kill-server` ends every session) |
| `termcheck: command not found` | `~/bin` not on `PATH` yet | Open a new shell, or `source ~/.bashrc` (zsh: `~/.zshenv`) |

---

## How it works

### Asking the terminal

`termcheck` writes five questions to the terminal and reads the answers:

| Question | Answer, e.g. | Tells it |
| --- | --- | --- |
| `ESC _Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA ESC \` (kitty image query) | `ESC _Gi=31;OK ESC \` | It takes kitty-protocol images |
| `ESC ]99;i=termcheck:p=?; ESC \` (kitty notification query) | `ESC ]99;i=termcheck:p=?;a=focus,report:... ESC \` | It shows OSC 99 notifications |
| `ESC [>0q` (XTVERSION) | `ESC P>\|Warp(v0.2026...) ESC \` | Its name and version |
| `ESC [14t` | `ESC [4;720;1440t` | Its text area in pixels |
| `ESC [c` (DA1) | `ESC [?62;4c` | 4 means sixel. Every terminal answers this, so it marks the end |

Terminals ignore questions they don't understand and answer the rest in order,
so the DA1 answer means there's nothing more to wait for. A terminal that never
answers costs 2 seconds. After the DA1 answer, `termcheck` waits another 0.3
seconds for stragglers, such as a second terminal attached to the same tmux
session, so that they don't turn up at your prompt as typed text.

### Through tmux and screen

Inside tmux and screen, the questions go out wrapped, so that they reach your
terminal instead of tmux or screen, which would answer some of them themselves.
The answers come back as if typed, and tmux and screen hand them to the
program. That was tested with tmux 3.1 and 3.7 and screen 4.8: the answers
arrived intact through all three. So `termcheck` learns your terminal's name
even inside screen and tmux before 3.3, which can't tell programs what your
terminal is. Inside mosh, it doesn't ask: mosh answers DA1 itself, as a plain
VT220, so the answer wouldn't be your terminal's.

```
remote machine                                                   your machine
termcheck ─► tmux / screen ─► sshd ══ SSH ══► ssh client ─► terminal
    ▲        (must pass it on)                                  │
    └──────────────────────── answers ◄─────────────────────────┘
```

tmux writes a wrapped sequence wherever your terminal's cursor is at that
moment, ahead of any text it hasn't drawn yet. So the `-t` images pause 50 ms
first, which lets tmux draw the label and put the cursor after it.

### How you're connected

On Linux, `termcheck` walks up the process tree in `/proc` from the shell, or
inside tmux from the tmux client you're using (`#{client_pid}`), looking for
`sshd` (or `sshd-session`, OpenSSH 9.8+) or `mosh-server`. That's why it can
tell SSH from mosh inside tmux, where `$SSH_CONNECTION` dates from when the
session started.

### What tmux knows

Inside tmux, `termcheck` also reads tmux's formats and options:
`#{version}`, `#{client_termtype}` and `#{allow-passthrough}` (3.3+),
`#{client_termname}`, `#{client_termfeatures}` (3.2+), `#{client_pid}`,
`set-clipboard` and `terminal-overrides`. A format that a tmux version doesn't
have comes out empty, which tells `termcheck` the version is older.

---

## Uninstall

```sh
rm ~/bin/termcheck
grep -n 'added by termcheck setup.sh' ~/.bashrc ~/.zshenv 2> /dev/null
```

The marker comment is followed by the one line that was added. Delete both with
`vi`, unless other tools in `~/bin` need it.

---

## Testing

`termcheck` and `setup.sh` were tested on Linux with bash 5.2 and 4.4, and pass
shellcheck. A small Python program stood in for the terminal: it ran each test
in a pseudo-terminal, recorded every byte that reached it, and answered the
questions the way the terminal it imitated would. It imitated Warp, kitty,
Ghostty, WezTerm, foot, XTerm, a terminal that answers only DA1, and one that
answers nothing, and PuTTY, answering as MobaXterm did on a real machine. The
example at the top of this README is `termcheck`'s output with the Warp
stand-in, inside tmux 3.7. A bash renamed `sshd` (or `mosh-server`) stood in
for the connection, since `termcheck` goes by process names.

| Path | What was checked |
| --- | --- |
| No multiplexer | Each imitated terminal was recognised by its XTVERSION answer; kitty's image and notification answers, and foot's and WezTerm's sixel, were picked up; XTerm, the DA1-only and the silent terminal gave `?` rows, the silent one after 2 seconds |
| tmux 3.7 | The questions went through passthrough and the answers came back (Warp, kitty, WezTerm). With only `allow-passthrough on`: `fix` for the clipboard (`set-clipboard external`), links and 24-bit colour, all three gone with the suggested lines. With `allow-passthrough off`: not asked, named from `#{client_termtype}`, and `fix` for notifications and images. A VTE stand-in, which takes no clipboard copies: clipboard `no`, and no `set-clipboard` line. A stand-in answering as tmux 3.5a (a tmux on your own machine): reported as that, with `?` rows |
| tmux 3.1 | Asked through passthrough (always on before 3.3); links `no`; 24-bit colour fixed with `terminal-overrides` |
| GNU screen 4.8 | Asked through DCS wrapping; iTerm2 recognised by `$LC_TERMINAL`; links and 24-bit colour `no` |
| GNU screen 5.0.2 (built from source) | Asked through DCS wrapping: the Warp and kitty stand-ins' answers came back intact, even when sent a byte at a time 50 ms apart. The PuTTY stand-in was recognised by its DA1 answer, and `-t` skipped the sixel test |
| mosh (stand-in) | Not asked; notifications, images and links `no` |

Also tested:

- **`-t`.** The bytes that reached the terminal were decoded: with no
  multiplexer, through tmux 3.7 and through screen 4.8, every test sequence
  arrived whole and unwrapped. Through tmux the link and the 24-bit colours
  came through, and through screen the colours were turned into basic ones.
  Through tmux, each image followed its label, in three runs out of three.
  Through screen 5.0.2 (with and without `truecolor on`) and tmux 3.7, the
  Warp stand-in got the prompt, then the kitty image's delete command after
  Enter, and after Ctrl-C (exit status 130). With no multiplexer there was no
  prompt.
- **Fixes.** A missing terminfo entry (`TERM=foot`) gave the `tic` command; an
  entry only under `~/.terminfo/78/` gave a warning and the link, and the link
  made `infocmp` find it; an entry only under `x/` gave a note; a damaged
  entry gave the `tic` command, not a link. Entries that the system also has
  gave nothing.
- **Edge cases.** No terminal at all (run from a script without one, with and
  without `-t`); `$TMUX` set with no tmux on `PATH`, or naming a server
  that has gone (tmux's error shown, `?` rows); `$TMUX` and `$STY` both set; `TERM=linux` with a VT102 DA1 answer (not taken for PuTTY); bad
  options. Ctrl-C while waiting for answers left echo on.
- **`setup.sh`**, in a throwaway `HOME`: bash (with an early `return` in
  `.bashrc`) and zsh, a re-run without duplicate lines, another `termcheck`
  earlier on `PATH`, and a repository path with a space in it.

On a real terminal: MobaXterm on Windows, over SSH and through screen 5.0.2,
answered the size question (`ESC [4;890;1884t`) and DA1 (`ESC [?6c`) and
nothing else. That's how the PuTTY family came to be recognised. It printed
the sixel test as text, which is why the test is now skipped there. After the
change, the same session was recognised as "PuTTY, KiTTY or MobaXterm", with
notifications and images `no`, 24-bit colour `ok` (screen 5.0.2 with
`truecolor on`), the X11 forwarding note, and no sixel test. A clipboard copy
(OSC 52) didn't reach the Windows clipboard, either through screen or outside
it.

Not tested: other real terminals (only the bytes they would receive and
send), mosh, macOS, and tmux control mode.

---

## References

- xterm control sequences (XTVERSION, DA1, `CSI 14 t`, OSC 52, sixel):
  <https://invisible-island.net/xterm/ctlseqs/ctlseqs.html>
- kitty graphics protocol: <https://sw.kovidgoyal.net/kitty/graphics-protocol/>
- kitty desktop notifications (OSC 99, and its query):
  <https://sw.kovidgoyal.net/kitty/desktop-notifications/>
- iTerm2 inline images: <https://iterm2.com/documentation-images.html>
- OSC 8 hyperlinks: <https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda>
- tmux: `man tmux` (`set-clipboard`, `allow-passthrough`, `terminal-features`,
  `client_termfeatures`), and its source, <https://github.com/tmux/tmux>:
  `input.c` (which OSC sequences it handles), `tty-features.c` (the terminals it
  recognises), `options-table.c` (defaults), `CHANGES` (versions)
- GNU screen source, `ansi.c` (OSC handling) and `process.c` (`truecolor`):
  <https://git.savannah.gnu.org/cgit/screen.git>
- mosh source, `src/terminal/terminalfunctions.cc`:
  <https://github.com/mobile-shell/mosh>
- Warp source, `crates/warp_terminal/src/model/ansi/mod.rs` (the OSC
  sequences it handles): <https://github.com/warpdotdev/warp>
