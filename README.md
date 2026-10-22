# AutoTyper

A small macOS app that types text you paste into it into any other app, letter by letter, like a person would: uneven speed, quick bursts inside words, pauses after punctuation and between paragraphs, and the occasional typo that gets noticed and fixed.

## Download

**[⬇ Download AutoTyper.zip](https://github.com/danyyttee2323/school-autotyper/releases/latest/download/AutoTyper.zip)**

Works on macOS 14 Sonoma or newer, on both Apple Silicon and Intel Macs.

### Easiest: one command

Paste this into Terminal. It downloads the app, puts it in Applications and opens it:

```bash
curl -fsSL https://github.com/danyyttee2323/school-autotyper/releases/latest/download/AutoTyper.zip -o /tmp/AutoTyper.zip && ditto -x -k /tmp/AutoTyper.zip /Applications && open /Applications/AutoTyper.app
```

### Or: download in the browser

1. Download the zip above and double-click it to unzip.
2. Drag **AutoTyper.app** into **Applications**.
3. Open it. macOS will say it can't verify the app, because it isn't signed with a paid Apple developer account. Click **Done**, go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.

## First run: allow Accessibility

AutoTyper needs Accessibility access to press keys in other apps. The first time you press **Start** it asks for it:

1. Click **Grant Access**.
2. Switch **AutoTyper** on in the list that opens.
3. AutoTyper restarts by itself with your text still there. Press **Start** again.

## How to use

1. Click where you want the text to go (a document, a note, a text box).
2. Switch to AutoTyper, paste your text, and set **Speed** (words per minute) and **Typos** (how often it makes a mistake).
3. Press **Start** (⌘↩). AutoTyper hides itself and your previous app comes back to the front. You have 5 seconds to click a different spot if you want. The Dock icon counts down, then shows progress.
4. Press **Esc**, or click AutoTyper in the Dock, to **pause**. Press **Resume** to continue from exactly where it stopped, so leave the cursor in place. **Start Over** begins again from the first letter.

Good to know:

- Line breaks are typed as Return, so in chat apps each line sends a message.
- The app you type into can still change the text (autocorrect, smart quotes, auto-closing brackets).
- Real pace is below the Speed setting because of pauses and typo fixes: 60 WPM types at roughly 40.

## Build from source

Needs the Xcode Command Line Tools (`xcode-select --install`).

```bash
./build.sh
```

This makes `AutoTyper.app` and `AutoTyper.zip`. Every new build has a new signature, so macOS asks for Accessibility again: press Start and click Grant Access.

Check the typing logic (typos and pause/resume always end with the exact text):

```bash
./AutoTyper.app/Contents/MacOS/AutoTyper --selftest
```
