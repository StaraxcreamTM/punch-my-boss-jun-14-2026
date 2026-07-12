# Punch My Boss

A self-contained HTML5 mini-game. Everything — code, styles, and embedded
assets — lives in a single file, so there's no build step and no dependencies.

## Play / run it

Just open the HTML file in a browser:

- **Double-click** `punch-my-boss-1.html`, or
- Run a local server (needed for microphone / voice features, which browsers
  block on `file://` pages):

  ```bash
  # from the repo folder
  python -m http.server 8000
  # then visit http://localhost:8000/punch-my-boss-1.html
  ```

## Project layout

| File | Purpose |
|------|---------|
| `punch-my-boss-1.html` | The entire game (HTML + CSS + JS + assets) |
| `README.md` | This file |

## Development

Because the game is one file, editing is straightforward — open
`punch-my-boss-1.html` and edit the `<style>`, `<script>`, or markup in place.

### Saving versions to GitHub

```bash
git add -A
git commit -m "Describe what changed"
git push
```
