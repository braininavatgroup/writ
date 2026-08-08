# Writ — user guide

macOS has no idea which of your audio devices you prefer. It switches to
whatever connected most recently, every time, forever. Writ is the list that
says otherwise.

---

## The idea

You give Writ an order. It keeps your Mac on the highest-ranked device that is
actually available, and puts you back there when something knocks you off.

There are two separate lists, one for **Input** and one for **Output**, because
the right answer differs: you almost always want your good microphone, but you
usually do want your headphones when you put them on.

## First run

Writ lives in the menu bar. It has no Dock icon and no main window — click the
headset icon to open it.

The list starts populated with everything currently connected, ranked by what
each device *is* rather than the order macOS happened to find them in. A USB
microphone outranks a headset; headphones outrank speakers; a monitor comes
last. Two rules are set for you:

- The **built-in microphone** is set to "only when the lid is open"
- **Display audio** — a monitor or TV over HDMI or DisplayPort — is set to
  "never use"

Both defaults exist because of how those devices misbehave, explained below.

## The list

- **Click a device** to switch to it now
- **Drag the grip** on the left to reorder
- The filled circle marks the device in use

Everything else lives in the **•••** menu on each row.

### Never use this device

A hard block. Writ will not select it, and if something else does, Writ takes
you off it.

This is the one to reach for with monitor speakers. A display announces itself
as an audio device the moment it wakes, and macOS will happily move your audio
there mid-sentence.

### Only use when the lid is open

For the built-in microphone, and set automatically.

When you close a MacBook's lid, the built-in mic is disconnected **in hardware**.
It still appears in every audio menu on the system, and it captures pure silence.
This rule exists so Writ never hands you a microphone that cannot hear you.

Built-in *speakers* are unaffected and work fine with the lid shut.

### Icon & Label

Rename a device and pick its glyph. Mostly cosmetic, with one important
exception — see AirPlay.

### Forget Device

Only offered for disconnected devices. Writ remembers devices by identifier so
that unplugging something never loses its rank; this is how you remove one for
good.

## AirPlay

macOS names every AirPlay target the same thing: `AirPlay`. Not "HomePod", not
the name you gave it — just `AirPlay`. Their identifiers also change every time
they reconnect.

So Writ does two things:

- **It never overrides AirPlay.** Sending audio to a HomePod is always something
  you did on purpose, in Control Center. Nothing connects to one by accident, so
  nothing should take you off one.
- **An unnamed AirPlay device is temporary.** It appears while it is playing and
  disappears afterwards, rather than leaving a pile of identical dead `AirPlay`
  rows in your list.

**Name it while it is playing** — that is the one moment you can tell which
speaker it is — and it becomes permanent, keeps its rank, and survives
reconnecting.

## The input meter

Under Input, Writ shows the level it is actually receiving. Three numbers:

| | |
|---|---|
| **pk** | Peak — the loudest moment, with a hold marker on the bar |
| **avg** | Rolling average — the level you are actually sitting at |
| **floor** | Noise floor — the room when you are not speaking |

Aim to peak just below the marker at 80%. If it says **Clipping**, lower your
input gain.

The floor is the interesting one. It is how you compare two microphones
honestly, and how you can see what Voice Isolation is doing: it barely moves
your speech level but pulls the floor down hard.

**Change…** opens Apple's microphone mode picker. macOS provides no way for an
app to set that mode, so this is a shortcut to the system control — the meter
keeps running behind it so you can hear the difference as you switch.

The meter runs only while the panel is open and showing Input. Close the panel
and the microphone is released.

## Keyboard shortcuts

Two are set out of the box and work from any app:

| | |
|---|---|
| **⌃⌥⌘M** | Mute or unmute the microphone |
| **⌃⌥⌘A** | Show or hide Writ |

Four more are available but unassigned: pause enforcing, restore priority order,
cycle input, cycle output. Set them under **Keyboard Shortcuts…** in the gear
menu.

Only two ship bound because a global shortcut is taken away from every other app
on your Mac, and that should be your decision rather than ours.

Writ registers these through the system's hot key service, which means it is
told when one specific combination is pressed and nothing else. It never asks
for Accessibility permission and cannot read your keyboard.

## Pausing

The switch in the header stops Writ changing anything. Your list is kept; it
simply stops being enforced. The menu bar icon shows a line through it while
paused.

Use this if you are doing something unusual with audio routing and want macOS
left alone.

**Restore Priority Order** in the gear menu re-applies your list — the undo for
a device you picked by hand.

## When Writ deliberately does nothing

It is worth knowing the cases where nothing happening is correct:

- **You are on AirPlay.** Left alone on purpose.
- **You picked a device by hand.** Respected until something connects or
  disconnects. Use Restore Priority Order to go back to your list.
- **Nothing eligible is connected.** Writ leaves you where you are rather than
  moving you somewhere worse.

## Troubleshooting

**The menu bar icon isn't there.**
Almost always a menu bar manager — Bartender, Ice, or similar — hiding
unrecognised items. Show Writ in that app's settings. ⌃⌥⌘A opens the panel
regardless.

**The meter says microphone access denied.**
System Settings → Privacy & Security → Microphone → enable Writ. The meter is
the only thing that uses it, and audio is measured and discarded, never
recorded.

**My monitor keeps stealing the audio.**
Set it to "never use" from its ••• menu. It should already be set that way — if
it connected before you installed Writ, set it by hand.

**My HomePod bounces back to the laptop speakers.**
Name it, using Icon & Label, while it is playing. An unnamed AirPlay device is
indistinguishable from any other and is treated as temporary.

**A device shows "not connected" but I'm using it.**
Its identifier changed. Forget it and let Writ re-add it.

## Uninstall

Quit Writ using the button at the bottom of the panel, then move it to the
Trash. To remove its settings as well:

```sh
defaults delete dance.braininavat.writ
```
