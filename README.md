# Translation (Omarchy plugin)

Translation plugin for Omarchy 4 (plugin id `translate.lookup`). Press a hotkey to translate the selected text, or type text into a small panel. Each request goes to exactly one provider: DeepL (default), Microsoft, Google, Yandex or LibreTranslate.

## Install

```bash
omarchy plugin add https://github.com/kolesnikof-ai/omarchy-translation-plugin.git --enable
~/.config/omarchy/plugins/translate.lookup/install.sh
```

`install.sh` links `omarchy-translate` into `~/.local/bin` and creates `~/.config/omarchy/translate/config.json` (mode 600). Put your API key there, then add the hotkey from `config/bindings.example.lua` to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + T", "Translate selection", "omarchy-translate")
```

## Use

- Select text anywhere and press the hotkey. With nothing selected, the panel opens with an input field.
- In the input field Enter translates and Shift+Enter inserts a line break. Esc or a click outside closes the panel.
- Copy the translation with the copy button, Ctrl+C or Super+C while the panel is open.
- `omarchy-translate --stdin` translates standard input and prints JSON; `--input` always opens the input field; `--copy` copies the last translation.

## Configuration

See `config/config.example.json`. Language codes are lowercase ISO 639-1 (`ru`, `en`, `de`). Words get part-of-speech variants only with the `microsoft` provider (`ui.max_variants` per part of speech). Set `ui.show_language_switcher` to `true` for source/target dropdowns inside the panel.

## Tests

```bash
bats tests
```

The tests mock `curl` and the Wayland/Omarchy commands, so they run without Omarchy. The QML panel can only be checked for syntax outside a live Omarchy session.
