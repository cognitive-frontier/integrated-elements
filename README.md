# The Integrated Element Lattice

Standalone interactive page. Single-file, no build step.

## Deploy

```
./deploy.sh <github-username> <repo-name>
```

The script will:

1. Pull your GitHub PAT from macOS Keychain (the one git already uses)
2. Create the repo on GitHub via the API
3. Initialize the local git repo, commit, push to `main`
4. Enable GitHub Pages (source: `main` branch, root)

Live URL after ~1 minute: `https://<github-username>.github.io/<repo-name>/`

## Run locally

```
python3 -m http.server 8000
```

Then open http://localhost:8000.
