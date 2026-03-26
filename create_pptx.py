#!/usr/bin/env python3
"""
Generate a PowerPoint deck for the App Gateway WAF -> Azure Firewall -> Web App demo.
"""

from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE

# ── Colour palette ──────────────────────────────────────────
AZURE_BLUE   = RGBColor(0x00, 0x78, 0xD4)
DARK_BLUE    = RGBColor(0x00, 0x2B, 0x5C)
WHITE        = RGBColor(0xFF, 0xFF, 0xFF)
LIGHT_GRAY   = RGBColor(0xF2, 0xF2, 0xF2)
GREEN        = RGBColor(0x10, 0x7C, 0x10)
RED          = RGBColor(0xD1, 0x34, 0x38)
ORANGE       = RGBColor(0xFF, 0x8C, 0x00)
BLACK        = RGBColor(0x00, 0x00, 0x00)
GRAY_TEXT    = RGBColor(0x60, 0x60, 0x60)

# ── Configuration — update these after deployment ───────────
# Run deploy.ps1 first, then fill in the values from deployment output
APPGW_PUBLIC_IP = "<your-appgw-public-ip>"     # App Gateway public IP from deployment output
CLIENT_IP       = "<your-client-ip>"            # Your public IP (visible at ifconfig.me)
WEBAPP_NAME     = "<your-webapp-name>"          # Web App name from deployment output
RESOURCE_GROUP  = "<your-resource-group>"       # Resource group name used in deployment
REGION          = "<your-region>"               # Azure region (e.g., westus2)

prs = Presentation()
prs.slide_width  = Inches(13.333)
prs.slide_height = Inches(7.5)

# ── Helper functions ────────────────────────────────────────
def add_bg(slide, color):
    bg = slide.background
    fill = bg.fill
    fill.solid()
    fill.fore_color.rgb = color

def add_text_box(slide, left, top, width, height, text, font_size=18,
                 bold=False, color=BLACK, alignment=PP_ALIGN.LEFT, font_name="Segoe UI"):
    txBox = slide.shapes.add_textbox(Inches(left), Inches(top), Inches(width), Inches(height))
    tf = txBox.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.text = text
    p.font.size = Pt(font_size)
    p.font.bold = bold
    p.font.color.rgb = color
    p.font.name = font_name
    p.alignment = alignment
    return txBox

def add_bullet_slide_content(slide, items, left=1.0, top=2.2, width=11.0, font_size=18, color=BLACK):
    txBox = slide.shapes.add_textbox(Inches(left), Inches(top), Inches(width), Inches(5.0))
    tf = txBox.text_frame
    tf.word_wrap = True
    for i, item in enumerate(items):
        if i == 0:
            p = tf.paragraphs[0]
        else:
            p = tf.add_paragraph()
        p.text = item
        p.font.size = Pt(font_size)
        p.font.color.rgb = color
        p.font.name = "Segoe UI"
        p.space_after = Pt(10)
        p.level = 0
    return txBox

def add_shape_box(slide, left, top, width, height, text, fill_color, text_color=WHITE, font_size=12):
    shape = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(left), Inches(top),
                                    Inches(width), Inches(height))
    shape.fill.solid()
    shape.fill.fore_color.rgb = fill_color
    shape.line.fill.background()
    shape.shadow.inherit = False
    tf = shape.text_frame
    tf.word_wrap = True
    tf.paragraphs[0].alignment = PP_ALIGN.CENTER
    p = tf.paragraphs[0]
    p.text = text
    p.font.size = Pt(font_size)
    p.font.bold = True
    p.font.color.rgb = text_color
    p.font.name = "Segoe UI"
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    return shape

def add_arrow(slide, left, top, width, height):
    shape = slide.shapes.add_shape(MSO_SHAPE.RIGHT_ARROW, Inches(left), Inches(top),
                                    Inches(width), Inches(height))
    shape.fill.solid()
    shape.fill.fore_color.rgb = AZURE_BLUE
    shape.line.fill.background()
    shape.shadow.inherit = False
    return shape

def add_slide_title(slide, title, subtitle=None):
    add_text_box(slide, 0.8, 0.4, 11.5, 0.8, title, font_size=32, bold=True, color=DARK_BLUE)
    if subtitle:
        add_text_box(slide, 0.8, 1.2, 11.5, 0.5, subtitle, font_size=16, color=GRAY_TEXT)

def add_slide_number(slide, num, total=12):
    add_text_box(slide, 12.0, 7.0, 1.2, 0.4, f"{num}/{total}", font_size=10, color=GRAY_TEXT,
                 alignment=PP_ALIGN.RIGHT)


# ═══════════════════════════════════════════════════════════════
# SLIDE 1 — Title Slide
# ═══════════════════════════════════════════════════════════════
slide = prs.slides.add_slide(prs.slide_layouts[6])  # blank
add_bg(slide, DARK_BLUE)

add_text_box(slide, 1.5, 1.5, 10.0, 1.5,
             "Azure Application Gateway (WAF)\n→ Azure Firewall → Web App",
             font_size=36, bold=True, color=WHITE, alignment=PP_ALIGN.CENTER)
add_text_box(slide, 1.5, 3.5, 10.0, 0.8,
             "Preserving Client IP with X-Forwarded-For Header",
             font_size=22, color=RGBColor(0x80, 0xBF, 0xEE), alignment=PP_ALIGN.CENTER)
add_text_box(slide, 1.5, 5.0, 10.0, 0.5,
             "Architecture Deep Dive & Live Demo",
             font_size=18, color=RGBColor(0xA0, 0xA0, 0xA0), alignment=PP_ALIGN.CENTER)
add_text_box(slide, 1.5, 6.2, 10.0, 0.5,
             "March 2026",
             font_size=14, color=RGBColor(0x80, 0x80, 0x80), alignment=PP_ALIGN.CENTER)
add_slide_number(slide, 1)


# ═══════════════════════════════════════════════════════════════
# SLIDE 2 — Problem Statement
# ═══════════════════════════════════════════════════════════════
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, WHITE)
add_slide_title(slide, "Problem Statement", "Why do we need this architecture?")

items = [
    "🔒  Web App must NOT be accessible directly from the Internet",
    "🛡️  All traffic must be inspected by Azure Firewall (L3/L4 + IDPS)",
    "🌐  WAF protection needed against OWASP Top 10 attacks (L7)",
    "📍  Web App needs the original client IP for geolocation & logging",
    "⚠️  Challenge: Azure Firewall SNATs traffic — changes source IP!",
    "✅  Solution: App Gateway preserves client IP in X-Forwarded-For header",
]
add_bullet_slide_content(slide, items, font_size=20)
add_slide_number(slide, 2)


# ═══════════════════════════════════════════════════════════════
# SLIDE 3 — Architecture Diagram
# ═══════════════════════════════════════════════════════════════
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, WHITE)
add_slide_title(slide, "Architecture Diagram", "Internet → App Gateway (WAF) → Azure Firewall → Web App (Private)")

# VNet box
vnet_shape = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(2.5), Inches(2.0),
                                     Inches(10.0), Inches(4.5))
vnet_shape.fill.solid()
vnet_shape.fill.fore_color.rgb = RGBColor(0xE8, 0xF0, 0xFE)
vnet_shape.line.color.rgb = AZURE_BLUE
vnet_shape.line.width = Pt(2)
add_text_box(slide, 2.7, 2.1, 3.0, 0.4, "VNet: 10.0.0.0/16", font_size=12, bold=True, color=AZURE_BLUE)

# Internet User
add_shape_box(slide, 0.3, 3.5, 1.8, 1.2, "☁️ Internet\nClient", RGBColor(0x60, 0x60, 0x60), WHITE, 14)
add_arrow(slide, 2.2, 3.9, 0.6, 0.4)

# App Gateway
add_shape_box(slide, 3.0, 2.8, 2.2, 2.2,
              "App Gateway\nWAF_v2\n\n10.0.0.0/24\n\nAdds\nX-Forwarded-For", AZURE_BLUE, WHITE, 11)
add_arrow(slide, 5.3, 3.9, 0.6, 0.4)

# Azure Firewall
add_shape_box(slide, 6.1, 2.8, 2.2, 2.2,
              "Azure Firewall\nPremium\n\n10.0.1.0/26\n\nIDPS + SNAT", RED, WHITE, 11)
add_arrow(slide, 8.4, 3.9, 0.6, 0.4)

# Web App (Private Endpoint)
add_shape_box(slide, 9.2, 2.8, 2.2, 2.2,
              "Web App\nPrivate EP\n\n10.0.3.0/24\n\nNo Public\nAccess", GREEN, WHITE, 11)

# UDR annotation
add_text_box(slide, 4.5, 5.3, 4.0, 0.6,
             "⬆ UDR: Route to PE subnet → Firewall (10.0.1.4) as next hop",
             font_size=11, bold=True, color=ORANGE)

# Header flow annotation
add_text_box(slide, 0.3, 6.2, 12.5, 0.5,
             f"X-Forwarded-For: {CLIENT_IP} (your real IP) → preserved through entire chain → Web App reads it from header",
             font_size=13, bold=True, color=GREEN)
add_slide_number(slide, 3)


# ═══════════════════════════════════════════════════════════════
# SLIDE 4 — Traffic Flow Detail
# ═══════════════════════════════════════════════════════════════
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, WHITE)
add_slide_title(slide, "Traffic Flow — Step by Step")

steps = [
    f"1️⃣  Client ({CLIENT_IP}) sends request to App Gateway public IP ({APPGW_PUBLIC_IP})",
    "2️⃣  App Gateway WAF inspects request (OWASP 3.2 rules) — blocks attacks",
    f"3️⃣  App Gateway adds X-Forwarded-For: {CLIENT_IP} header",
    "4️⃣  App Gateway resolves backend FQDN via Private DNS → 10.0.3.4 (PE IP)",
    "5️⃣  UDR on AppGW subnet intercepts: route 10.0.3.0/24 → Azure Firewall (10.0.1.4)",
    "6️⃣  Azure Firewall Premium inspects (IDPS signatures) + SNATs the traffic",
    "7️⃣  Traffic arrives at Web App Private Endpoint (10.0.3.4)",
    "8️⃣  Web App reads original client IP from X-Forwarded-For header ✅",
]
add_bullet_slide_content(slide, steps, font_size=18)
add_slide_number(slide, 4)


# ═══════════════════════════════════════════════════════════════
# SLIDE 5 — Key Design Decisions
# ═══════════════════════════════════════════════════════════════
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, WHITE)
add_slide_title(slide, "Key Design Decisions")

items = [
    "🎯  Backend Pool = Web App FQDN (not Firewall IP)",
    "     → Firewall doesn't understand HTTP; health probes would fail",
    "     → UDR silently routes data-plane traffic through Firewall",
    "",
    "🔄  Firewall SNAT forced on private ranges (privateRanges: 255.255.255.255/32)",
    "     → Ensures symmetric routing — return traffic goes back through Firewall",
    "",
    "🔐  Web App: publicNetworkAccess = Disabled",
    "     → Only reachable via Private Endpoint inside the VNet",
    "",
    "📊  Log Analytics with diagnostic settings on both AppGW and Firewall",
    "     → Full audit trail of every request and its original client IP",
]
add_bullet_slide_content(slide, items, font_size=16)
add_slide_number(slide, 5)


# ═══════════════════════════════════════════════════════════════
# SLIDE 6 — X-Forwarded-For Explained
# ═══════════════════════════════════════════════════════════════
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, WHITE)
add_slide_title(slide, "X-Forwarded-For — How It Works",
                "The HTTP header that preserves the original client IP through proxies")

items = [
    f"Client sends request → Source IP: {CLIENT_IP}",
    "",
    "App Gateway receives it → adds header:",
    f"     X-Forwarded-For: {CLIENT_IP}",
    "",
    "Azure Firewall SNATs → network source IP changes to 10.0.1.4",
    "     But the HTTP header is untouched! (L4 device, doesn't modify L7 headers)",
    "",
    "Web App receives the request:",
    "     • Remote Address (TCP): 10.0.1.4  ← Firewall's IP (SNAT'd)",
    f"     • X-Forwarded-For header: {CLIENT_IP}  ← YOUR real IP ✅",
    "",
    "⭐ The app reads X-Forwarded-For to get the real client IP for geolocation/logging",
]
add_bullet_slide_content(slide, items, font_size=16)
add_slide_number(slide, 6)


# ═══════════════════════════════════════════════════════════════
# SLIDE 7 — Deployed Resources
# ═══════════════════════════════════════════════════════════════
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, WHITE)
add_slide_title(slide, "Deployed Resources", f"Resource Group: {RESOURCE_GROUP} ({REGION})")

resources = [
    "Resource                        │ Name / Value",
    "────────────────────────────── │ ──────────────────────────────────────",
    f"App Gateway (WAF_v2)           │ demoapp-appgw  •  PIP: {APPGW_PUBLIC_IP}",
    "WAF Policy                       │ demoapp-waf-policy  •  OWASP 3.2 Prevention",
    "Azure Firewall (Premium)      │ demoapp-fw  •  Private IP: 10.0.1.4",
    "Firewall Policy + IDPS          │ demoapp-fw-policy  •  IDPS: Alert mode",
    "Virtual Network                   │ demoapp-vnet  •  10.0.0.0/16",
    f"Web App                           │ {WEBAPP_NAME}",
    "Private Endpoint                 │ demoapp-webapp-pe  •  IP: 10.0.3.4",
    "Private DNS Zone                │ privatelink.azurewebsites.net",
    "Route Table + UDR               │ demoapp-appgw-rt  •  → Firewall next hop",
    "Log Analytics                      │ demoapp-law  •  30-day retention",
]
add_bullet_slide_content(slide, resources, font_size=14, left=0.8)
add_slide_number(slide, 7)


# ═══════════════════════════════════════════════════════════════
# SLIDE 8 — Demo: HTTP Echo Proof
# ═══════════════════════════════════════════════════════════════
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, WHITE)
add_slide_title(slide, "Demo 1: HTTP Echo — Instant Proof",
                f"curl http://{APPGW_PUBLIC_IP} returns all headers the Web App received")

items = [
    f"Command:  curl http://{APPGW_PUBLIC_IP}",
    "",
    "Key headers in the JSON response:",
    "",
    f'  x-forwarded-for:    {CLIENT_IP}:59633, 10.0.0.4',
    f"      └→ {CLIENT_IP} = YOUR real public IP ✅",
    "      └→ 10.0.0.4 = App Gateway's internal IP",
    "",
    '  x-client-ip:          10.0.0.4',
    "      └→ After Firewall SNAT — NOT your real IP",
    "",
    f'  x-original-host:    {APPGW_PUBLIC_IP} (App Gateway public IP)',
    '  x-appgw-trace-id:  67b3304c... (proves it went through AppGW)',
    "",
    "⭐ Web App can use X-Forwarded-For for geolocation, rate limiting, logging",
]
add_bullet_slide_content(slide, items, font_size=15)
add_slide_number(slide, 8)


# ═══════════════════════════════════════════════════════════════
# SLIDE 9 — Demo: App Gateway Access Logs
# ═══════════════════════════════════════════════════════════════
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, WHITE)
add_slide_title(slide, "Demo 2: App Gateway Access Logs",
                "Portal → Log Analytics (demoapp-law) → Logs")

items = [
    "KQL Query:",
    "  AzureDiagnostics",
    "  | where ResourceType == 'APPLICATIONGATEWAYS'",
    "  | where Category == 'ApplicationGatewayAccessLog'",
    "  | project TimeGenerated, clientIP_s, requestUri_s, httpStatus_d, serverRouted_s",
    "",
    "Live results from our deployment:",
    "",
    "  clientIP_s          │ httpStatus │ serverRouted_s",
    "  ─────────────────│──────────│────────────────",
    f"  {CLIENT_IP}       │ 200           │ 10.0.3.4:443",
    "  <client-ip-1>    │ 200           │ 10.0.3.4:443",
    "  <client-ip-2>    │ 200           │ 10.0.3.4:443",
    "",
    "✅ clientIP_s = each caller's REAL public IP",
    "✅ serverRouted_s = 10.0.3.4 (Web App Private Endpoint)",
]
add_bullet_slide_content(slide, items, font_size=14)
add_slide_number(slide, 9)


# ═══════════════════════════════════════════════════════════════
# SLIDE 10 — Demo: WAF Logs
# ═══════════════════════════════════════════════════════════════
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, WHITE)
add_slide_title(slide, "Demo 3: WAF Firewall Logs — Attacks Blocked!",
                "Portal → Log Analytics → ApplicationGatewayFirewallLog")

items = [
    "KQL Query:",
    "  AzureDiagnostics",
    "  | where Category == 'ApplicationGatewayFirewallLog'",
    "  | project TimeGenerated, clientIp_s, ruleId_s, action_s, Message",
    "",
    "Live results — WAF is already blocking real scanners:",
    "",
    "  clientIp_s           │ action    │ Message",
    "  ──────────────── │ ─────── │ ─────────────────────────────",
    "  <client-ip-3>     │ Blocked  │ Anomaly Score Exceeded (missing UA)",
    "  <client-ip-4>     │ Blocked  │ Bot detected — Unspecified identity",
    "  <client-ip-5>     │ Matched │ Host header is numeric IP",
    "",
    "✅ WAF actively protecting against OWASP attacks",
    "✅ clientIp_s = attacker's real IP for forensic investigation",
    "✅ Legitimate requests with proper User-Agent pass through",
]
add_bullet_slide_content(slide, items, font_size=14)
add_slide_number(slide, 10)


# ═══════════════════════════════════════════════════════════════
# SLIDE 11 — Demo: Direct Access Blocked
# ═══════════════════════════════════════════════════════════════
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, WHITE)
add_slide_title(slide, "Demo 4: Web App NOT Accessible Directly",
                "Proving the Web App is locked down to Private Endpoint only")

items = [
    "Test direct access to the Web App:",
    f"  curl https://{WEBAPP_NAME}.azurewebsites.net  → 403 Forbidden ❌",
    "",
    "Expected result: ❌ Connection refused / 403 Forbidden",
    "  → publicNetworkAccess is set to Disabled",
    "  → No public inbound traffic is allowed",
    "",
    "Test through App Gateway:",
    f"  curl http://{APPGW_PUBLIC_IP}",
    "",
    "Expected result: ✅ 200 OK with full JSON response",
    "  → Traffic flows: AppGW → Firewall → Private Endpoint → Web App",
    "",
    "⭐ This proves the Web App is ONLY reachable through the secure chain",
]
add_bullet_slide_content(slide, items, font_size=17)
add_slide_number(slide, 11)


# ═══════════════════════════════════════════════════════════════
# SLIDE 12 — Summary
# ═══════════════════════════════════════════════════════════════
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, DARK_BLUE)

add_text_box(slide, 1.0, 0.6, 11.0, 0.8, "Summary", font_size=36, bold=True,
             color=WHITE, alignment=PP_ALIGN.CENTER)

summary_items = [
    "✅  Web App secured — only accessible via Private Endpoint",
    "✅  WAF (OWASP 3.2) blocks L7 attacks at the App Gateway",
    "✅  Azure Firewall Premium inspects all traffic (L3/L4 + IDPS)",
    "✅  X-Forwarded-For preserves original client IP through the entire chain",
    "✅  Firewall SNAT ensures symmetric routing",
    "✅  Full audit trail via Log Analytics (AppGW + Firewall logs)",
    "",
    "📍  Use case: Geolocation, rate limiting, compliance logging",
    "🔗  Microsoft reference: aka.ms/azfw-appgw",
]
txBox = slide.shapes.add_textbox(Inches(1.5), Inches(2.0), Inches(10.0), Inches(5.0))
tf = txBox.text_frame
tf.word_wrap = True
for i, item in enumerate(summary_items):
    p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
    p.text = item
    p.font.size = Pt(20)
    p.font.color.rgb = WHITE
    p.font.name = "Segoe UI"
    p.space_after = Pt(8)

add_slide_number(slide, 12)


# ── Save ────────────────────────────────────────────────────
output_path = "AppGW-Firewall-WebApp-Demo.pptx"
prs.save(output_path)
print(f"✅ Presentation saved to: {output_path}")
print(f"   Slides: {len(prs.slides)}")
