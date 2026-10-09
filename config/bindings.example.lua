-- Add to ~/.config/hypr/bindings.lua

-- Translate the current selection. With nothing selected the panel opens with
-- an input field instead. SUPER + SHIFT + T is free in Omarchy 4.0.x defaults.
o.bind("SUPER + SHIFT + T", "Translate selection", "omarchy-translate")

-- Optional: always open the input field, whatever is selected. Useful when the
-- primary selection stays filled after you deselect text.
-- o.bind("SUPER + ALT + T", "Translate typed text", "omarchy-translate --input")

-- Optional fallback: copy the last translation to the clipboard from a hotkey.
-- Only needed if Super+C does not reach the open panel on your setup.
-- o.bind("SUPER + ALT + C", "Copy last translation", "omarchy-translate --copy")
