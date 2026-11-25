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
    "<b>For ePHI,</b> use codex-home run, codex-home vscode-project, or Finder's Open in Codex "
    "Project. Plain codex and ordinary VS Code bypass checks. Confirm the Toolkit route and "
    "exact model each session. "
    + link("ePHI requirements", "docs/umgpt.md#check-data-permissions-first"),
    MARGIN, 684, WIDTH, SMALL,
)

left = section("1  Get ready", [
    ("text", f"Follow {link('Installation', 'INSTALLATION.md')} to install prerequisites, "
     "clone, and review the checkout before running its scripts."),
    ("code", 'cd "$HOME/Developer/codex-contexts"\nexport PATH="$PWD/bin:$PATH"\ncodex-home help'),
    ("text", "Adjust the clone path as needed. The export sets PATH for this shell; "
     f"see {link('Installation', 'INSTALLATION.md#3-clone-and-validate')} to make it persistent, "
     "or use <b>./bin/codex-home</b> from the clone."),
    ("text", "<b>Admin rights:</b> none for the helper. Initial Homebrew installation "
     "or Linux <b>apt</b> may need an administrator. Run the helper without sudo."),
], MARGIN, 638)
left = section("2  Add a ChatGPT account", [
    ("code", "codex-home create-subscription work\ncodex-home login work\n"
     "codex-home run work login status"),
    ("text", "<b>work</b> is a local label. Check the account and workspace in the browser. "
     "For an API key, pick one of the API setup blocks on this page."),
], MARGIN, left)
section("Or use the U-M GPT Toolkit", [
    ("small", "Check the provider URL before entering the key at the hidden prompt."),
    ("code", "codex-home create-umgpt\n"
     "codex-home show umgpt\n"
     "codex-home set-key umgpt"),
    ("small", "Use <b>umgpt-low</b> only for low-sensitivity data. "
     f"{link('U-M setup and tool-call test', 'docs/umgpt.md')} | "
     f"{link('Model defaults', 'MODELS.md')}."),
], MARGIN, left)

right = section("3  Select an identity for a project", [
    ("text", "Use your project path and an existing identity, such as <b>work</b>. "
     "The project's .envrc selects its CODEX_HOME."),
    ("code", 'P="/path/to/project"\ncodex-home project work "$P"'),
    ("text", "Read <b>.envrc</b> and the workspace as text. <b>direnv allow</b> lets "
     "the shell run .envrc with your user permissions."),
    ("code", 'direnv allow "$P"\ncd "$P"\ndirenv exec . codex-home current\ndirenv exec . codex-home run'),
    ("text", "Expect <b>WORK</b>. For VS Code, run <b>codex-home vscode-project</b> "
     "in the folder. Start a new chat and check the extension's account. "
     f"{link('Verification', 'docs/commands.md#check-the-selected-identity')}."),
    ("small", "For a one-off terminal session, enter the folder and run "
     "<b>codex-home run work</b> to choose the identity explicitly."),
], RIGHT, 638)
section("Or add a custom API provider", [
    ("code", "codex-home create-api lab-api \\\n  https://api.example.org/v1 \\\n  MODEL_ID LAB_API_KEY\ncodex-home show lab-api"),
    ("text", "Check the displayed base URL, then enter the key at the hidden prompt."),
    ("code", "codex-home set-key lab-api"),
    ("small", f"{link('API providers', 'docs/api-providers.md')}: compatibility, tool-call test, "
     "Azure, and billing."),
], RIGHT, right)

footer(1, "Keep credentials and identity homes outside Git, shared drives, and cloud sync. "
       + link("Credential storage", "docs/security.md#where-data-lives"))
pdf.showPage()

header(2, "Everyday commands and security options")
paragraph(
    '<b>codex-home run</b> uses the active context selected by direnv. Add <b>NAME</b> '
    'for an explicit choice. Set <b>P="/path/to/project"</b> below. Commands assume '
    '<b>codex-home</b> is on PATH.',
    MARGIN, 679, WIDTH,
)

left = section("Open and check", [
    ("code", 'cd "$P"\ndirenv exec . codex-home current\ndirenv exec . codex-home run\n'
     'codex-home vscode-project'),
    ("text", "With the shell hook, use <b>current</b> and <b>run</b> directly. "
     "CLI model/session: <b>/status</b>. "
     "IDE: profile menu + model picker. "
     f"{link('Verification', 'docs/commands.md#check-the-selected-identity')}."),
], MARGIN, 638)
left = section("Change or disconnect a project", [
    ("text", "Close the project's VS Code window first:"),
    ("code", 'codex-home project-change NAME "$P"\ncodex-home project-review "$P"'),
    ("text", "Read and close the review window, then approve and open:"),
    ("code", 'direnv allow "$P"\ncodex-home vscode-project "$P"'),
    ("text", "To disconnect the folder, <b>reset permanently deletes the generated files</b>. "
     f"Back them up if needed. {link('Removal guide', 'docs/remove-folder-context.md')}."),
    ("code", 'codex-home project-reset "$P"'),
], MARGIN, left)
section("Optional sandbox defaults", [
    ("code", "codex-home set-sandbox work workspace-write"),
    ("small", "Sets native command sandbox and user approval defaults. Reload VS Code "
     "and start a new chat; verify active permissions. "
     f"{link('Boundaries and overrides', 'docs/security.md#optional-native-sandbox')}."),
], MARGIN, left)

right = section("Provider checks and API keys", [
    ("text", "Confirm the base URL before entering a key. Doctor and models may contact the provider. "
     "Revoke replaced keys with the provider."),
    ("code", "codex-home show NAME\ncodex-home doctor NAME\ncodex-home models NAME\ncodex-home set-key NAME"),
    ("text", "Wrong ChatGPT login? Reauthenticate only that identity:"),
    ("code", "codex-home run NAME logout\ncodex-home login NAME"),
], RIGHT, 638)
right = section("Extra environment variables", [
    ("small", "New API identities fetch their stored key through a credential command, "
     "outside the editor environment. Proxies and extra variables require opt-in:"),
    ("code", "CODEX_CONTEXTS_ENV_ALLOW='HTTPS_PROXY' \\\n  codex-home run work"),
    ("small", "Use exact names separated by spaces. Managed API keys stay out of the environment; "
     f"loader variables stay blocked. {link('Environment policy', 'docs/security.md#secret-exposure-boundaries')}."),
], RIGHT, right)
right = section("Finder on macOS", [
    ("text", "Install from the clone directory:"),
    ("code", "./bin/install-macos-open-with"),
    ("text", "Right-click a folder: <b>Quick Actions &gt; Open in Codex Project</b> "
     "(or <b>Services</b>). Choose its identity and review the generated files. "
     "Use this launcher or the helper to reopen with the intended identity. "
     f"{link('Uninstall instructions', 'docs/macos-open-with.md#uninstall-the-finder-integration')}."),
], RIGHT, right)

footer(2, "<b>Before approving a command:</b> check the action, target paths, and network destination. "
       "Confirm your provider and workflow are approved for research data. "
       + link("Understand approvals", "docs/security.md#what-an-approval-allows") + " | "
       + link("Full commands", "docs/commands.md"))
pdf.save()
print(OUTPUT)
