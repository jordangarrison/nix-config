// Stand-in for the two runtime values the extensions under test import from
// pi. The real package lives inside the pi binary; installing it from npm pulls
// a large dependency graph (see packages/pi-extensions/default.nix).

/** pi formats this from the user's keybindings; the default binding is ctrl+o. */
export const keyHint = (_keybinding, description) => `ctrl+o ${description}`;

const identity = (text) => text;

/** Every MarkdownTheme style as identity, without syntax highlighting. */
export const getMarkdownTheme = () =>
  Object.fromEntries(
    [
      "heading", "link", "linkUrl", "code", "codeBlock", "codeBlockBorder", "quote",
      "quoteBorder", "hr", "listBullet", "bold", "italic", "strikethrough", "underline",
    ].map((key) => [key, identity]),
  );
