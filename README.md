# lidawake

Keep your Mac running with the lid closed, like the "do nothing when I close the lid" setting on Windows.

Shut the lid and put it in your bag, and whatever you left running carries on. It gives up before it does any harm: at 15% battery, or after 3 minutes of serious heat, the Mac goes to sleep as normal and you get a phone alert if you've set one up.

It keeps the Mac awake, not online. See [Before you rely on it](#before-you-rely-on-it).

## What you need

- A MacBook on macOS 11 or later
- The admin password for that Mac
- Apple's command line tools (the installer tells you what to run if they're missing)

If IT manages your Mac, check with them first. The installer adds a small admin rule, explained in [How it works](#how-it-works).

So far it has only run on one Mac, an M1 MacBook Air on macOS 14.8.5. It should work on other MacBooks, but see [What has been tested](#what-has-been-tested).

## Install

```sh
git clone https://github.com/oli3dwards/lidawake.git
cd lidawake
./install.sh
```

macOS asks for your password once. A laptop icon then appears in your menu bar, and lid-closed mode is on. macOS may also tell you a background item was added, which is expected.

The installer keeps its own copy, so you can delete this folder afterwards. To update, run `git pull` and `./install.sh` again from a clone.

## Using it

The menu bar icon shows what it's doing and has an on/off switch. The same things work from the terminal:

| Command | What it does |
| --- | --- |
| `lidawake` | Shows what it's doing and whether it's set up properly |
| `lidawake on` / `lidawake off` | Turns lid-closed mode on or off |
| `lidawake log` | Shows the last 30 log lines (`lidawake log 100` for more) |
| `lidawake uninstall` | Removes it and puts lid-close sleep back to normal |

If `lidawake` isn't found, the installer will have printed a line to add to `~/.zshrc`.

## Phone alerts

Set this up. Without it, your Mac can go to sleep in your bag and you won't know. The alert needs an internet connection at that moment. With none, the Mac still sleeps, and the failed alert is only in the log.

Alerts use [ntfy](https://ntfy.sh), which is free. Anyone who knows your topic name can read your alerts or send you some, so use a random one:

1. Install the ntfy app on your phone.
2. Run this, and copy the name it prints:

   ```sh
   topic="lidawake-$(openssl rand -hex 12)"
   conf="$HOME/Library/Application Support/lidawake/config.sh"
   echo "NTFY_TOPIC=$topic" >> "$conf"
   chmod 600 "$conf"
   echo "$topic"
   ```

3. Subscribe to that name in the app.
4. Send yourself a test: `curl -d "lidawake test" "ntfy.sh/$topic"`

## Settings

Add any of these to `~/Library/Application Support/lidawake/config.sh`. They apply at the next check, usually within 30 seconds.

| Setting | Default | What it does |
| --- | --- | --- |
| `LOW_BATTERY` | `15` | Cut out at this battery percentage |
| `RESUME_BATTERY` | `20` | Carry on again once the battery is back to this level |
| `HOT_SECONDS` | `180` | How long the Mac must stay seriously hot before it cuts out |
| `NTFY_TOPIC` | none | Your phone alert topic |
| `NTFY_SERVER` | `https://ntfy.sh` | Your own ntfy server, if you have one |

## Before you rely on it

- **Awake doesn't mean online.** Wi-Fi works with the lid shut, but only on a network the Mac can join. On the move with no hotspot, it has no internet, so anything that needs a connection stalls until you're back on Wi-Fi.
- **Bags get hot.** A running laptop in a bag has nowhere to lose heat, and a MacBook Air has no fan. The heat cut-out is a safety net, not a reason to run heavy work in a closed bag.
- **Log in after a restart.** The checks only run while you're logged in, but macOS remembers the switch. After a restart, the Mac sits at the login screen unable to sleep and with no battery or heat checks, so log in before you shut the lid. The same goes if you log out.
- **It can sleep a docked Mac.** With the lid shut and an external screen attached, a cut-out sleeps the Mac after 2 minutes with no keyboard or mouse input.
- **It relies on a hidden macOS feature.** Apple doesn't document it, so an update could change it. Run `lidawake` after a macOS update to check it's still on.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| `lidawake: command not found` | Add the line the installer printed to `~/.zshrc`, or run `~/.local/bin/lidawake` |
| It says permission is missing | Run `./install.sh` again from a clone |
| Warning triangle in the menu bar | The background check has stopped. Run `lidawake`, then `./install.sh` again if needed |
| The Mac slept when you didn't expect it | Run `lidawake log`. It records every check and every cut-out |
| The Mac won't sleep at all | Run `lidawake off`. If lidawake is already gone, run `sudo pmset -a disablesleep 0` |

## How it works

macOS has no setting for this, but `/usr/bin/pmset` has an option that isn't in its manual:

```sh
sudo pmset -a disablesleep 1
```

This sets `SleepDisabled`, which stops the Mac sleeping when the lid shuts. On its own it's risky, because nothing would ever turn it off again. lidawake is the safety layer around it:

- **About every 20 seconds** a background job runs `lidawake tick`. On battery, macOS can stretch this to around 30. It reads the battery, macOS's own heat rating, the lid state and how long since anyone touched the keyboard or mouse.
- **`lib/decide.sh`** holds the rules: stay awake, or let go of the switch. A battery cut-out holds until mains power or 20%, so it can't flip on and off.
- **At a cut-out with the lid shut,** it turns the switch off, alerts your phone once and sleeps the Mac, once nobody has touched it for 2 minutes.
- **The admin rule** is `/etc/sudoers.d/lidawake`. It lets your user run exactly two commands without a password, `pmset -a disablesleep 0` and `pmset -a disablesleep 1`, and nothing else.

| What | Where |
| --- | --- |
| Installed copy | `~/Library/Application Support/lidawake/app/` |
| Settings, log and state | `~/Library/Application Support/lidawake/` |
| Background jobs | `~/Library/LaunchAgents/io.github.oli3dwards.lidawake*.plist` |
| Admin rule | `/etc/sudoers.d/lidawake` |

## What has been tested

| Check | Result |
| --- | --- |
| Stays awake with the lid shut, on battery | Passed on a real Mac: two runs of 114 and 79 minutes, 29 and 30 October 2026 |
| Stays online with the lid shut | Partly. It rejoined known Wi-Fi with the lid shut in both runs, but had no connection for about 80% of that time, in what looks like time away from Wi-Fi |
| Install, on/off and uninstall | Passed on a real Mac |
| The rules, plus install and uninstall failures | Passed in automated tests, with macOS's commands faked |
| Sleeping at a cut-out, and the phone alert | **Not yet proven on a real Mac.** Automated tests only |

To close that last gap, set up phone alerts, then run this from a clone and follow what it prints. It takes about 5 minutes, and you'll need to unplug the Mac and shut the lid:

```sh
bash tests/lid-test.sh
```

## Running the automated tests

```sh
bash tests/test_decide.sh
bash tests/test_cli.sh
```

These can't touch your real sleep setting: they run in a throwaway home folder with macOS's commands faked, and refuse to start if the fakes aren't in place.
