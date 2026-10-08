<p align="center">
  <img src="docs/icon.png" width="160" alt="ClipBar, a clipboard manager for macOS">
</p>

<h1 align="center">ClipBar: Clipboard Manager for macOS</h1>

<p align="center">
  <b>A free, open-source clipboard history for the Mac menu bar, built with SwiftUI and Liquid Glass.</b><br>
  Locked items behind Touch ID · automatic screenshots · text recognition in images · instant paste
</p>

<p align="center">
  <a href="https://github.com/SajjadMohabati/clipbar-mac/releases/latest"><img src="https://img.shields.io/github/v/release/SajjadMohabati/clipbar-mac?label=download&color=7c5cff" alt="Download the latest release"></a>
  <img src="https://img.shields.io/badge/macOS-26%20Tahoe-black?logo=apple" alt="macOS 26 Tahoe">
  <img src="https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-555" alt="Universal binary">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/SajjadMohabati/clipbar-mac?color=2ea44f" alt="MIT license"></a>
  <a href="https://github.com/SajjadMohabati/clipbar-mac/stargazers"><img src="https://img.shields.io/github/stars/SajjadMohabati/clipbar-mac?style=social" alt="GitHub stars"></a>
</p>

<p align="center">
  <a href="https://github.com/SajjadMohabati/clipbar-mac/releases/latest"><b>⬇️ Download ClipBar</b></a>
  &nbsp;·&nbsp; <a href="#features">Features</a>
  &nbsp;·&nbsp; <a href="#keyboard-shortcuts">Shortcuts</a>
  &nbsp;·&nbsp; <a href="#faq">FAQ</a>
</p>

<p align="center">
  <img src="docs/panel.png" width="440" alt="ClipBar clipboard history panel with Liquid Glass design on macOS Tahoe">
</p>

<p align="center"><a href="README.fa.md">🇮🇷 فارسی</a></p>

<p align="center"><sub>Created by <a href="https://github.com/SajjadMohabati"><b>Sajjad Mohabati</b></a></sub></p>

---

## Why ClipBar?

Most clipboard managers stop at "remember what I copied". ClipBar also keeps your **sensitive data
locked**, **catches every screenshot**, **reads the text inside images** and **pastes straight into the
app you were using**, while looking like it shipped with macOS Tahoe.

- 🔐 **Touch ID–locked items.** Card numbers, IDs and passwords are kept in the macOS Keychain, not in a plain file, and every paste, copy, edit or delete asks for Touch ID or your Mac password.
- 📸 **Screenshots go straight into your history.** Press ⇧⌘3 or ⇧⌘4 and the screenshot is on the clipboard and in ClipBar, ready to paste. No extra step.
- 🔎 **Search inside images.** Text in copied images and screenshots is recognized on-device, so you can find a screenshot by what's written in it.
- ⚡️ **Paste where you were typing.** Pick an item with `↩` and ClipBar pastes it into the focused text field of the previous app. `⌘1`–`⌘9` paste the first nine items instantly.
- 🫧 **Real Liquid Glass.** A native SwiftUI interface made for macOS 26: glass panel, glass controls, smooth motion, light and dark mode.
- 🛡 **Private by design.** No account, no cloud, no analytics and not a single network request. Everything stays on your Mac.
- 🪶 **Tiny and dependency-free.** About 3,000 lines of Swift, zero third-party packages, a universal binary for Apple silicon and Intel.

## Features

### Clipboard history
- Remembers **text, links, colors, images and files** copied from Finder, with the app it came from and when.
- **Filters**: All · Pinned · Text · Links · Images · Files (`⇥` to switch).
- **Instant search** across text, titles and the text recognized in images.
- **Pin** important snippets to the top and **drag to reorder**. Drag any row into another app to drop its content there.
- Copying the same thing again moves it to the top instead of making a duplicate, and counts how often you use it.
- **Auto cleanup** by age (1–365 days) and size (50–2,000 items); pinned items can be kept forever.

### Saved items and locking
- A separate **Saved** list for things you paste again and again: card number, student ID, address, email signature.
- Add them with **+** or move any history item in with `⌘S`. Saved items are never cleaned up automatically.
- **Lock an item** and its value moves into the **macOS Keychain**. It is shown as `••••••••` and needs **Touch ID or your password** to paste, copy, view, edit or delete.
- After unlocking, you have 30 seconds to do a few things without being asked again.
- Locked values you paste are marked as *concealed*, so other clipboard tools don't record them.

### Screenshots and images
- New screenshots (⇧⌘3, ⇧⌘4, ⇧⌘5) are **added to the history and copied to the clipboard** automatically.
- ClipBar follows the screenshot location you choose in ⇧⌘5 → Options, even if you change it later.
- **On-device text recognition (OCR)** with Apple's Vision framework makes text in images searchable and copyable.

### Pasting
- **Direct paste**: `↩` pastes into the app you were using, `⌥↩` only copies.
- **`⌘1`–`⌘9`** paste the first nine items without moving the selection.
- The panel never steals focus, so the text field you were typing in stays focused.

### Editor and transforms
- View and edit any item in a full editor with an inspector: character, word and line counts, link details, color values (HEX, RGB, HSL) and image text.
- **One-click transforms**: UPPERCASE, lowercase, Capitalize Words, trim whitespace, remove empty lines, sort, deduplicate or join lines, format or minify JSON, Base64 encode/decode, URL encode/decode.

### Privacy and security
- Skips anything password managers mark as **confidential or transient** (1Password, Bitwarden, KeePassXC and others that follow [nspasteboard.org](http://nspasteboard.org)).
- Automatically ignores **private keys, API tokens** (GitHub, OpenAI, Stripe, AWS, Slack, Google and more) and **credit card numbers** (validated with the Luhn check).
- **Pause capturing** any time from the menu bar icon's right-click menu.
- No network access at all. Your history is stored only in `~/Library/Application Support/ClipBar/`.

### Native and lightweight
- Menu bar app with a **custom global shortcut** (default `⇧⌘V`) and launch at login.
- Liquid Glass design, full keyboard control, light and dark mode.
- Universal binary for **Apple silicon and Intel**, written in Swift 6 with SwiftUI and AppKit.

## Install

**Requirements:** macOS 26 Tahoe or later, on Apple silicon or Intel.

### Download (recommended)

1. Download **`ClipBar-2.1.dmg`** from the [latest release](https://github.com/SajjadMohabati/clipbar-mac/releases/latest).
2. Open it and drag **ClipBar** onto **Applications**.

<p align="center">
  <img src="docs/installer.png" width="520" alt="ClipBar installer window">
</p>

3. Open ClipBar. Because it's an independent open-source app that isn't notarized by Apple, macOS
   shows a warning the first time. Click **Done**, open **System Settings → Privacy & Security**,
   scroll down and click **Open Anyway**. You only do this once.

   Prefer Terminal? This does the same thing:

   ```bash
   xattr -dr com.apple.quarantine /Applications/ClipBar.app
   ```

4. Press **`⇧⌘V`** or click the clipboard icon in the menu bar.

### Allow pasting

To paste directly into other apps, ClipBar needs **Accessibility** access. Click **Allow…** in the
panel, or turn on ClipBar in **System Settings → Privacy & Security → Accessibility**. Without it,
ClipBar still copies the item and you press `⌘V` yourself.

### Build from source

Requires the Swift 6 toolchain (Xcode 26 or the Command Line Tools).

```bash
git clone https://github.com/SajjadMohabati/clipbar-mac.git
cd clipbar-mac
./build.sh install
```

| Command | Result |
| --- | --- |
| `./build.sh` | Builds `ClipBar.app` in the project folder |
| `./build.sh install` | Builds, copies to `/Applications` and launches |
| `./build.sh dmg` | Builds a universal binary and the installer at `dist/ClipBar-<version>.dmg` |

<details>
<summary>Keep Accessibility access between your own builds</summary>

Builds are ad-hoc signed, so macOS treats every rebuild as a new app and the old Accessibility
entry stops working (it stays switched on but does nothing). Remove it with **−** and add ClipBar
again, or sign with a stable certificate: in Keychain Access choose
*Certificate Assistant → Create a Certificate…*, name it `ClipBar Local` and set the type to
**Code Signing**. Then build with:

```bash
CLIPBAR_SIGN_IDENTITY="ClipBar Local" ./build.sh install
```
</details>

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| `⇧⌘V` | Open ClipBar (change it in Settings) |
| `↑` `↓` | Move the selection |
| `↩` | Paste the selected item |
| `⌥↩` | Copy without pasting |
| `⌘1`–`⌘9` | Paste item 1–9 |
| `⇥` / `⇧⇥` | Next / previous filter |
| `⌘[` / `⌘]` | History / Saved |
| `⌘S` | Move to Saved |
| `⌘P` | Pin or unpin |
| `⌘E` | View and edit |
| `⌘⌫` | Delete |
| `⌘,` | Settings |
| `Esc` | Clear the search, then close |

## FAQ

<details>
<summary><b>Is ClipBar free?</b></summary>

Yes. ClipBar is free and open source under the MIT license, with no subscription, account or in-app purchase.
</details>

<details>
<summary><b>Does ClipBar send my clipboard anywhere?</b></summary>

No. ClipBar makes no network requests. Your history is stored only on your Mac in
`~/Library/Application Support/ClipBar/`, and locked values are stored in your macOS Keychain.
</details>

<details>
<summary><b>How do I keep a credit card number or password safe in ClipBar?</b></summary>

Add it to **Saved** with **+** and turn on **Lock with Touch ID**. The value moves into the Keychain,
is hidden in the list and needs Touch ID or your Mac password every time you use it.
</details>

<details>
<summary><b>Why isn't my screenshot showing up right away?</b></summary>

macOS saves a screenshot only after its floating thumbnail disappears, about five seconds later.
Open ⇧⌘5 → Options and turn off **Show Floating Thumbnail** to get it instantly. Screenshots taken
with **Control** held (⌃⇧⌘3 / ⌃⇧⌘4) go straight to the clipboard and appear in ClipBar immediately.
</details>

<details>
<summary><b>Why does macOS ask for Desktop or Pictures access?</b></summary>

That's where macOS saves screenshots. ClipBar reads that one folder to add new screenshots to your
history. You can turn screenshot capture off in Settings → Screenshots.
</details>

<details>
<summary><b>Does it work on Intel Macs and older macOS versions?</b></summary>

It runs on both Apple silicon and Intel Macs. It needs macOS 26 Tahoe, because the interface is
built on the Liquid Glass APIs introduced there.
</details>

## Your data

Everything lives in `~/Library/Application Support/ClipBar/`:

- `history.json`: your clipboard history
- `saved.json`: saved items (locked values are in the Keychain, never in this file)
- `Images/`: copied images, stored once as PNG files even if you copy them many times

To start over, quit ClipBar and delete that folder.

## Project layout

```
Sources/ClipBar/
  App.swift                menu bar item, panel, windows, keyboard handling
  ClipView.swift           the menu bar panel
  EditorView.swift         item viewer and editor window
  SettingsView.swift       settings window
  Store.swift              history model, capture, cleanup, persistence
  Clipboard.swift          pasteboard I/O, secret detection, image storage, OCR
  Vault.swift              Keychain storage and Touch ID for locked items
  ScreenshotWatcher.swift  picks up new screenshots from the screenshot folder
  Transforms.swift         text transforms
  HotKey.swift             global shortcut
  Settings.swift           preferences
scripts/
  make-icon.swift          renders the app icon
  make-dmg-background.swift renders the installer background
```

## Contributing

Bug reports, ideas and pull requests are welcome. Open an
[issue](https://github.com/SajjadMohabati/clipbar-mac/issues) to start a conversation.
If ClipBar saves you time, a ⭐️ on GitHub helps other people find it.

## Author

Created by **Sajjad Mohabati** · [github.com/SajjadMohabati](https://github.com/SajjadMohabati)

## License

[MIT](LICENSE) © Sajjad Mohabati

<sub>Keywords: clipboard manager for Mac, clipboard history macOS, menu bar clipboard app, macOS Tahoe clipboard, Liquid Glass app, free clipboard manager, open source clipboard manager, copy paste history Mac, Touch ID clipboard, screenshot to clipboard, OCR clipboard, SwiftUI menu bar app.</sub>
