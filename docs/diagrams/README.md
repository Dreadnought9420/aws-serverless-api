# Diagrams

## Source

[`architecture.drawio`](architecture.drawio) is the single source of truth. It
uses the official AWS architecture icon set (`mxgraph.aws4.*`) and the GitHub
mark, so services are recognisable at a glance rather than being generic boxes.

## Exporting

Needs the [draw.io desktop](https://github.com/jgraph/drawio-desktop/releases)
CLI on `PATH`.

```bash
make diagram
```

which runs:

```bash
drawio -x -f png -e -s 2 -o docs/diagrams/architecture.drawio.png docs/diagrams/architecture.drawio
drawio -x -f svg -e    -o docs/diagrams/architecture.svg          docs/diagrams/architecture.drawio
```

`-e` embeds the diagram XML in the exported file, so
`architecture.drawio.png` stays editable — opening it in draw.io recovers the
full diagram. The double extension signals that.

### On Windows

There is no `make` on Windows and the Makefile needs bash, so call the CLI
directly from PowerShell in the repository root:

```powershell
# Find the binary (system-wide install, then per-user fallback)
$drawio = @(
  "C:\Program Files\draw.io\draw.io.exe",
  "$env:LOCALAPPDATA\Programs\draw.io\draw.io.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
$drawio    # prints the path, or nothing if draw.io desktop is not installed

# Export
& $drawio -x -f png -e -s 2 -o "docs\diagrams\architecture.drawio.png" "docs\diagrams\architecture.drawio"
& $drawio -x -f svg -e    -o "docs\diagrams\architecture.svg"          "docs\diagrams\architecture.drawio"

# Repair the truncated IEND chunk draw.io leaves in -e PNGs
python scripts\repair_drawio_png.py docs\diagrams\architecture.drawio.png

# Check it against the 512KB pre-commit ceiling
Get-ChildItem docs\diagrams\architecture.* |
  Select-Object Name, @{n="KB";e={[math]::Round($_.Length/1KB)}}
```

If the PNG comes out over 512KB, either drop `-s 2` to `-s 1`, point the README
at `architecture.svg` instead, or raise `--maxkb` in `.pre-commit-config.yaml`.

On a headless Linux box, wrap the export in `xvfb-run -a`.

## Editing without installing anything

Open [app.diagrams.net](https://app.diagrams.net), choose **File → Open from →
Device**, and pick `architecture.drawio`. Nothing is uploaded — the file is
parsed client-side.

## Conventions

| Element | Style |
| --- | --- |
| AWS services | `mxgraph.aws4.resourceIcon` with the official service colour |
| GitHub | `mxgraph.weblogos.github` |
| Grouping | `mxgraph.aws4.group` — solid for the AWS Cloud boundary, dashed for regions |
| Request path | Solid dark arrow |
| Telemetry and notifications | Dashed pink arrow |
| CI/CD control plane | Dotted purple arrow |

Keep the legend in sync with the arrow styles actually used. Snap coordinates to
multiples of 10 so the diagram stays aligned to draw.io's grid and is pleasant to
hand-edit.

## Regenerating a Mermaid fallback

The README carries a Mermaid version so the architecture renders on GitHub
without an exported image. It is maintained by hand — Mermaid cannot express the
icons — but a structural starting point can be generated with the drawio skill's
`drawio2mermaid.py`.
