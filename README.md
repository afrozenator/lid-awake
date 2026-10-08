# Lid Awake

A small native macOS menu-bar app with explicit **Enable** and **Disable** controls for keeping a MacBook running with its lid closed.

## Build and use

Requires macOS 13 or later and Apple's Command Line Tools (`xcode-select --install`).

```sh
./build.sh
open "$HOME/Applications/Lid Awake.app"
```

Click **Enable**, approve the macOS administrator prompt, and check that the menu bar says **Awake ON**. Click **Disable** to allow normal sleep again. Closing the controls window leaves the menu-bar app running; use **Show Controls** to reopen it. Launching the app never enables the setting automatically.

The app offers **Disable & Quit** while enabled. Cancelling authorization keeps the app open. The actual system setting is checked every five seconds and after each change.

## Terminal control

After building:

```sh
./lid-awake enable
./lid-awake disable
./lid-awake status
./lid-awake open
```

`on` and `off` are aliases for `enable` and `disable`. Changes use the same macOS authorization prompt as the app. No password is stored.

## How it works

Enable runs `/usr/bin/pmset -a disablesleep 1`; Disable runs `/usr/bin/pmset -a disablesleep 0`. These are the only commands the app can execute with administrator privileges. It verifies that macOS applied the requested setting and reports errors.

This changes the global `SleepDisabled` flag. It prevents system sleep, including lid-close and manually requested sleep, on battery and wall power. The display sleep timer, screen-lock settings, and other power settings are unchanged. Other applications may still prevent sleep after you disable Lid Awake.

`disablesleep` exists in [Apple's pmset source](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m), but is undocumented in its manual; behavior may change in macOS updates. See also [Apple's kernel sleep policy](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/IOPMrootDomain.cpp).

## Operating limits

- The setting persists until disabled, including across restarts. If the app crashes or is force-quit while enabled, reopen it and click **Disable**, or run the recovery command below.
- There is no automatic timeout, battery cutoff, or temperature control. Keep the Mac on a ventilated surface and disable before putting it in a bag.
- Sleep prevention does not bypass Claude permission prompts, keep a terminated process alive, or guarantee network connectivity. Keep Claude and its terminal running.

Recovery command:

```sh
sudo /usr/bin/pmset -a disablesleep 0
```

No downloads, system daemon, or login item are installed. To uninstall, disable, quit, and delete `~/Applications/Lid Awake.app`.

## Verification

`build.sh` compiles and locally signs the app, runs ten non-mutating parser and command-selection checks, then reads the Mac's real status. The UI was inspected on an Apple silicon Mac running macOS 26.6. Administrator-authorized changes and physical lid-close behavior require a local hardware test; the automated checks do not validate these.

Enable the app and run this in Terminal, close the lid for a minute on a ventilated desk, reopen it, then press Control-C:

```sh
while true; do date '+%H:%M:%S'; sleep 5; done
```

Continuous timestamps across the closed-lid interval indicate the Mac stayed awake. Disable when finished.
