#!/usr/bin/env python3
"""Build the two-page reference: python3 docs/build-cheatsheet.py

Requires ReportLab (python3 -m pip install reportlab).
"""

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph


OUTPUT = Path(__file__).with_name("codex-contexts-cheatsheet.pdf")
REPO = "https://github.com/FritscheLab/codex-contexts"
NAVY = colors.HexColor("#00274C")
MAIZE = colors.HexColor("#FFCB05")
INK = colors.HexColor("#172B3A")
MUTED = colors.HexColor("#455868")
PALE = colors.HexColor("#F2F5F8")
RULE = colors.HexColor("#CDD5DC")
PAGE_W, PAGE_H = letter
MARGIN = 34
GAP = 22
WIDTH = PAGE_W - 2 * MARGIN
COL = (WIDTH - GAP) / 2
RIGHT = MARGIN + COL + GAP

BODY = ParagraphStyle(
    "body", fontName="Helvetica", fontSize=10, leading=13.2,
    textColor=INK, spaceAfter=6,
)
SMALL = ParagraphStyle(
    "small", parent=BODY, fontSize=9, leading=11.5, textColor=MUTED,
)


def link(label, path):
    return f'<link href="{REPO}/blob/main/{path}" color="#005A9C"><u>{label}</u></link>'


def paragraph(text, x, y, width, style=BODY):
    item = Paragraph(text, style)
    _, height = item.wrap(width, PAGE_H)
    item.drawOn(pdf, x, y - height)
    return y - height - 6


def code(text, x, y, width):
    lines = text.splitlines()
    size, leading, padding = 9, 12, 8
    for line in lines:
        if stringWidth(line, "Courier", size) > width - 2 * padding:
            raise ValueError(f"Command too wide: {line}")
    height = len(lines) * leading + 2 * padding
    pdf.setFillColor(PALE)
    pdf.roundRect(x, y - height, width, height, 3, fill=1, stroke=0)
    pdf.setFillColor(INK)
    pdf.setFont("Courier", size)
    for index, line in enumerate(lines):
        pdf.drawString(x + padding, y - padding - size - index * leading, line)
    return y - height - 8


def section(title, items, x, y):
    pdf.setFillColor(NAVY)
    pdf.setFont("Helvetica-Bold", 12)
    pdf.drawString(x, y - 12, title)
    pdf.setStrokeColor(RULE)
    pdf.setLineWidth(0.5)
    pdf.line(x, y - 19, x + COL, y - 19)
    y -= 27
    for kind, text in items:
        if kind == "code":
            y = code(text, x, y, COL)
        elif kind == "small":
            y = paragraph(text, x, y, COL, SMALL)
        else:
            y = paragraph(text, x, y, COL)
    if y < 104:
        raise ValueError(f"Section extends into footer: {title} ({y:.1f})")
    return y - 11


def header(page, subtitle):
    pdf.setFillColor(MUTED)
    pdf.setFont("Helvetica-Bold", 8.5)
    pdf.drawString(MARGIN, 765, "FRITSCHE LAB  /  UNIVERSITY OF MICHIGAN")
    pdf.drawRightString(PAGE_W - MARGIN, 765, f"CHEATSHEET  {page} / 2")
    pdf.setFillColor(NAVY)
    pdf.setFont("Helvetica-Bold", 27)
    pdf.drawString(MARGIN, 728, "Codex Contexts")
    pdf.setFont("Helvetica", 12)
    pdf.drawString(MARGIN, 706, subtitle)
    pdf.setFillColor(MAIZE)
    pdf.rect(MARGIN, 693, WIDTH, 3, fill=1, stroke=0)


def footer(page, note):
    pdf.setFillColor(PALE)
    pdf.roundRect(MARGIN, 48, WIDTH, 45, 4, fill=1, stroke=0)
    paragraph(note, MARGIN + 10, 83, WIDTH - 20, SMALL)
    pdf.setFont("Helvetica", 8)
    pdf.setFillColor(MUTED)
    pdf.drawString(MARGIN, 30, "github.com/FritscheLab/codex-contexts")
    pdf.linkURL(REPO, (MARGIN, 27, MARGIN + 190, 40), relative=0)
    pdf.drawRightString(PAGE_W - MARGIN, 30, f"MIT License  |  {page} / 2")


pdf = canvas.Canvas(str(OUTPUT), pagesize=letter, invariant=1, pageCompression=1)
pdf.setTitle("Codex Contexts - Cheatsheet")
pdf.setAuthor("Fritsche Lab, University of Michigan")
pdf.setSubject("Setup and everyday commands for separate Codex accounts and API providers")
pdf.setKeywords("Codex Contexts, Codex, direnv, VS Code, accounts, API, cheatsheet")

header(1, "Set up once on each computer")
paragraph(
    "A project's <b>.envrc</b> selects one <b>CODEX_HOME</b>. That home keeps its login, "
    "provider settings, and sessions. Several projects can share one identity.",
    MARGIN, 679, WIDTH,
)

left = section("1  Get ready", [
    ("text", f"Follow {link('Installation', 'INSTALLATION.md')} to install prerequisites "
     "and clone the repository. Then, in the clone:"),
    ("code", 'cd "$HOME/Developer/codex-contexts"\n./tests/test.sh\nexport PATH="$PWD/bin:$PATH"'),
    ("text", "For future zsh shells, put this line in <b>~/.zshrc</b>:<br/>"
     "<b>export PATH=~/Developer/codex-contexts/bin:$PATH</b><br/>"
     "Open a new terminal. Adjust the path if your clone is elsewhere, or use "
     "<b>./bin/codex-home</b> from the clone."),
    ("text", "<b>Admin rights:</b> none for the helper. Initial Homebrew installation "
     "or Linux <b>apt</b> may need an administrator. Run the helper without sudo."),
], MARGIN, 638)
left = section("2  Add ChatGPT accounts", [
    ("code", "codex-home create-subscription personal\ncodex-home login personal\n\n"
     "codex-home create-subscription work\ncodex-home login work"),
    ("text", "Check the account and workspace in each browser login. "
     "<b>personal</b> and <b>work</b> are labels, not verified plan names."),
], MARGIN, left)
section("Or use the U-M GPT Toolkit", [
    ("code", "codex-home create-umgpt\n"
     "codex-home create-umgpt-low\n"
     "codex-home set-key NAME"),
    ("small", f"Models — repo: <b>config/umgpt-models.toml</b>; local: "
     f"<b>~/.codex-homes/umgpt-models.toml</b>; live: <b>models NAME</b>. "
     f"<b>reset-umgpt-defaults</b> adopts repo values. <b>umgpt-low</b> is "
     f"<b>LOW-SENSITIVITY ONLY</b>. "
     f"{link('Guide', 'docs/umgpt.md')}."),
], MARGIN, left)

right = section("3  Select an identity for a project", [
    ("text", "Replace the path below with your project. Use an identity you have "
     "already created, such as <b>work</b>."),
    ("code", 'P="/path/to/project"\ncodex-home project work "$P"'),
    ("text", "Read the generated <b>.envrc</b>, then approve it and open VS Code:"),
    ("code", 'direnv allow "$P"\ncodex-home vscode work "$P"'),
    ("text", "Check <b>[CODEX: WORK]</b> in the window title. Start a new chat "
     "and use <b>/status</b> to confirm the account and provider."),
], RIGHT, 638)
right = section("Or add a custom API provider", [
    ("code", "codex-home create-api lab-api \\\n  https://api.example.org/v1 \\\n  MODEL_ID LAB_API_KEY\ncodex-home set-key lab-api"),
    ("text", "Replace the example URL and MODEL_ID. The provider must support "
     "bearer keys, the Responses API, streaming, and Codex tool calls."),
    ("text", f"Follow {link('API providers', 'docs/api-providers.md')} for a tool-call "
     "test, Azure setup, and billing details. A model list alone is not a compatibility test."),
], RIGHT, right)
section("Terminal only", [
    ("code", 'cd "/path/to/project"\ncodex-home run work'),
    ("text", "The tab/window title shows <b>[CODEX: WORK]</b>. "
     "Check the account with <b>/status</b>. No direnv or VS Code needed."),
], RIGHT, right)

footer(1, "<b>Keep it local.</b> Credentials belong in the identity home, outside Git and "
       "cloud sync. Generated project files contain local paths; review them before "
       "<b>direnv allow</b>. Repeat setup on every computer.")
pdf.showPage()

header(2, "Everyday commands and quick fixes")
paragraph(
    '<b>codex-home run</b> uses the active context selected by direnv. Add <b>NAME</b> '
    'for an explicit choice. Set <b>P="/path/to/project"</b> below. Commands assume '
    '<b>codex-home</b> is on PATH.',
    MARGIN, 679, WIDTH,
)

left = section("Open and check", [
    ("code", 'cd "$P"\ncodex-home run\ncodex-home vscode-project'),
    ("code", "codex-home current\ncodex-home show NAME\ncodex-home list"),
    ("text", "Confirm the account with <b>/status</b> in Codex."),
], MARGIN, 638)
left = section("Change or remove a project context", [
    ("text", "Close the project's VS Code window first. To select another identity:"),
    ("code", 'codex-home project-change NAME "$P"\ncodex-home project-review "$P"\ndirenv allow "$P"\ncodex-home vscode-project "$P"'),
    ("text", "Read and close the review window before approval. "
     "Start a new Codex chat."),
    ("code", 'codex-home project-reset "$P"'),
    ("text", "Reset removes untouched generated files and local Git exclusions. "
     "It keeps identity homes and credentials."),
], MARGIN, left)
section("Share personal skills", [
    ("code", "codex-home share-skills-all\ncodex-home share-skills NAME"),
    ("text", "Links <b>~/.codex/skills</b> and skips conflicts. "
     "Rerun after adding skills; review shared updates."),
], MARGIN, left)

right = section("Provider checks and API keys", [
    ("code", "codex-home doctor NAME\ncodex-home models NAME\ncodex-home set-key NAME"),
    ("text", "<b>doctor</b> may use the network; <b>models</b> needs a /models route. "
     "<b>set-key</b> hides your input. Revoke replaced keys with the provider."),
    ("text", "Wrong ChatGPT login? Reauthenticate only that identity:"),
    ("code", "codex-home run NAME logout\ncodex-home login NAME"),
], RIGHT, 638)
right = section("Quick fixes", [
    ("text", "<b>Wrong account:</b> relaunch with <b>codex-home vscode</b> "
     "and start a new chat."),
    ("text", "<b>Change refused:</b> files may be edited, tracked, "
     f"or incomplete. Follow {link('manual recovery', 'docs/projects-vscode.md#manual-recovery-for-a-custom-or-shared-setup')}."),
    ("text", "<b>HTTP 401/403:</b> check the key, URL, access, and network. "
     "Never print the key."),
    ("text", "<b>/responses fails:</b> confirm streaming Responses and tool-call "
     "support. Chat Completions alone is insufficient."),
], RIGHT, right)
right = section("Finder on macOS", [
    ("text", "Install from the clone directory:"),
    ("code", "./bin/install-macos-open-with"),
    ("text", "Right-click a folder: <b>Quick Actions &gt; Open in Codex Project</b> "
     "(or <b>Services</b>). Dock hover label: <b>VS Code - NAME</b>. "
     "After quitting, use Finder or the helper again; do not pin the editor copy. "
     f"{link('Uninstall instructions', 'docs/macos-open-with.md#uninstall-the-finder-integration')}."),
], RIGHT, right)

footer(2, "<b>Before using research data:</b> confirm approval for your provider, model, "
       "and workflow. Separate identities are not a security sandbox. "
       + link("Full commands", "docs/commands.md") + " | "
       + link("Troubleshooting", "docs/troubleshooting.md") + " | "
       + link("Security", "docs/security.md"))
pdf.save()
print(OUTPUT)
