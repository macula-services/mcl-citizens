"""Generate mcl-citizens' two C4 diagrams into assets/.

Run:  python3 architecture/c4_diagrams.py

  c4-context.svg     Level 1: what the service talks to
  c4-components.svg  Level 2: what it is made of

Drawn from the code, never from a template: the callbacks in
mcl_citizens_service.erl, the three responders and the admission policy, the
directory and the federation listener, the dependencies in rebar.config, and the
environment in config/sys.config.src and deploy/docker-compose.yml. When one of
those changes, the diagram changes in the same commit.

Colours are plain classes with a prefers-color-scheme: dark block, no CSS custom
properties (rsvg-convert renders those black), so the SVGs render the same on
GitHub, in IDE previews and through rsvg-convert. After a change, render each
(rsvg-convert -w 1400 assets/c4-context.svg -o /tmp/c.png) and look at it; keep
architecture/README.md's tables in step.
"""
import os
from xml.sax.saxutils import escape

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")

SANS = '"Atkinson Hyperlegible", "Segoe UI", system-ui, -apple-system, Helvetica, Arial, sans-serif'
MONO = '"JetBrains Mono", ui-monospace, Menlo, Consolas, monospace'

# Element kinds, each (light fill, light stroke, dark fill, dark stroke).
KINDS = {
    "b-sys": ("#F5E9CC", "#A56F0A", "#3A2E13", "#E3AA3C"),   # in scope
    "b-per": ("#E3EBF2", "#3B5B7A", "#1D2A36", "#8EB4D8"),   # person
    "b-mac": ("#E6E4EE", "#5E5A78", "#26243A", "#A9A4C8"),   # Macula infrastructure
    "b-ext": ("#ECEFED", "#8A9791", "#1C2421", "#7D8B85"),   # external system
    "b-cmp": ("#FFFFFF", "#8A9791", "#171F1C", "#7D8B85"),   # component or container
}

STYLE = f"""<style>
.t-name {{ font-family: {SANS}; font-size: 15px; font-weight: 700; }}
.t-desc {{ font-family: {SANS}; font-size: 12.5px; }}
.t-rel {{ font-family: {SANS}; font-size: 11.5px; paint-order: stroke; stroke-width: 4px; stroke-linejoin: round; }}
.t-code {{ font-family: {MONO}; font-size: 13px; font-weight: 600; }}
.t-type {{ font-family: {MONO}; font-size: 11.5px; }}
.t-bound {{ font-family: {MONO}; font-size: 12px; font-weight: 600; }}
.t-leg {{ font-family: {SANS}; font-size: 12px; }}
.edge {{ fill: none; stroke-width: 1.25; }}
.edge-later {{ fill: none; stroke-width: 1.25; stroke-dasharray: 5 4; }}
.bg {{ fill: #FFFFFF; }}
""" + "".join(f".{k} {{ fill: {v[0]}; stroke: {v[1]}; stroke-width: {2 if k == 'b-sys' else 1.25}; }}\n" for k, v in KINDS.items()) + """\
.b-later { fill: none; stroke: #8A9791; stroke-width: 1.25; stroke-dasharray: 5 4; }
.bound { fill: none; stroke: #B3BDB8; stroke-width: 1; }
.head { fill: #3B5B7A; }
.t-name, .t-code { fill: #16201D; }
.t-type, .t-bound, .t-leg { fill: #66736E; }
.t-desc { fill: #34413C; }
.t-rel { fill: #66736E; stroke: #FFFFFF; }
.edge, .edge-later { stroke: #8A9791; }
.arrowhead { fill: #8A9791; }
@media (prefers-color-scheme: dark) {
.bg { fill: #171F1C; }
""" + "".join(f".{k} {{ fill: {v[2]}; stroke: {v[3]}; }}\n" for k, v in KINDS.items()) + """\
.b-later { stroke: #7D8B85; }
.bound { stroke: #4A5752; }
.head { fill: #8EB4D8; }
.t-name, .t-code { fill: #E6ECE9; }
.t-type, .t-bound, .t-leg { fill: #93A09A; }
.t-desc { fill: #C3CDC8; }
.t-rel { fill: #93A09A; stroke: #171F1C; }
.edge, .edge-later { stroke: #7D8B85; }
.arrowhead { fill: #7D8B85; }
}
</style>"""

DEFS = ('<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
        'orient="auto-start-reverse"><path class="arrowhead" d="M0 0L10 5L0 10z"/></marker></defs>')

LEGEND = [("b-sys", "In scope"), ("b-per", "Person"), ("b-mac", "Macula infrastructure"),
          ("b-ext", "External system"), ("b-cmp", "Container or component")]
BOUNDARY = ("bound", "Boundary")


class Diagram:
    def __init__(self, name, title, w, h):
        self.name, self.title, self.w, self.h, self.parts = name, title, w, h, []

    def text(self, cls, x, y, s, anchor=None, rotate=None):
        a = f' text-anchor="{anchor}"' if anchor else ""
        r = f' transform="rotate({rotate} {x} {y})"' if rotate is not None else ""
        self.parts.append(f'<text class="{cls}" x="{x}" y="{y}"{a}{r}>{escape(s)}</text>')

    def box(self, cls, x, y, w, h, name, kind, desc, person=False, code=False):
        # A box that is too small for its own words renders as text on top of the
        # next box, which no test would catch and a reader would read as the
        # diagram saying something it does not. Fail here instead.
        need = 70 + 16 * max(len(desc) - 1, 0) + 18
        if h < need:
            raise ValueError(f"{self.name}: {name} needs height {need}, has {h}")
        for line in desc:
            if 16 + 6.2 * len(line) > w - 16:
                raise ValueError(f"{self.name}: {name}: '{line}' is wider than {w - 32}px")
        self.parts.append(f'<rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}" rx="10"/>')
        tx = x + 16
        if person:
            self.parts.append(f'<circle class="head" cx="{x + 26}" cy="{y + 24}" r="9"/>')
            tx = x + 44
        self.text("t-code" if code else "t-name", tx, y + 28, name)
        self.text("t-type", tx, y + 46, kind)
        for i, line in enumerate(desc):
            self.text("t-desc", x + 16, y + 70 + 16 * i, line)

    def bound(self, x, y, w, h, label):
        self.parts.append(f'<rect class="bound" x="{x}" y="{y}" width="{w}" height="{h}" rx="12"/>')
        self.text("t-bound", x + 16, y + 22, label)

    def edge(self, d, later=False):
        self.parts.append(f'<path class="{"edge-later" if later else "edge"}" d="{d}" marker-end="url(#a)"/>')

    def legend(self, y, boundary=True):
        x = 24
        for cls, label in LEGEND + ([BOUNDARY] if boundary else []):
            self.parts.append(f'<rect class="{cls}" x="{x}" y="{y}" width="22" height="14" rx="3"/>')
            self.text("t-leg", x + 30, y + 12, label)
            x += 34 + 6.6 * len(label)

    def write(self):
        svg = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" role="img" '
               f'aria-label="{escape(self.title)}">', f"<title>{escape(self.title)}</title>", STYLE, DEFS,
               f'<rect class="bg" x="0" y="0" width="{self.w}" height="{self.h}"/>'] + self.parts + ["</svg>", ""]
        with open(os.path.join(OUT, self.name), "w") as f:
            f.write("\n".join(svg))


def context():
    d = Diagram("c4-context.svg", "mcl-citizens system context", 1000, 690)
    d.box("b-per", 40, 30, 280, 120, "Citizen", "[Person]",
          ["An agent, or the operator of a node,", "that registers itself and reads the",
           "directory"], person=True)
    d.box("b-per", 690, 30, 270, 120, "Service operator", "[Person]",
          ["Deploys the release and supplies", "the realm, the stations and the",
           "instance list"], person=True)
    d.box("b-sys", 365, 200, 270, 152, "mcl-citizens", "[mcl_om mesh service, own box]",
          ["register_presence, list_citizens and", "get_citizen are its own procedures;",
           "mcl_om adds open info and get_limits;", "capabilities/0 is the list. /health is",
           "a Unix socket; the directory is ETS"])
    d.box("b-ext", 365, 420, 270, 136, "Other mcl-citizens instances", "[External: federation peers]",
          ["Each registration is a fact on", "the directory topic. A peer is",
           "heard only when its node id is in", "the configured publisher list"])
    d.box("b-mac", 40, 420, 280, 120, "macula-realm", "[Macula infrastructure]",
          ["Endorses the node's identity key", "and grants the org mcl-citizens,",
           "whose procedures it advertises"])
    d.box("b-mac", 680, 420, 280, 120, "Macula stations, mesh DHT", "[Macula infrastructure]",
          ["Stations from the environment are", "its entry points (QUIC); the DHT",
           "takes the capabilities it advertises"])
    d.edge("M180 150V180H400V200")
    d.text("t-rel", 200, 160, "calls register_presence,")
    d.text("t-rel", 200, 176, "list_citizens, get_citizen")
    d.edge("M825 150V180H620V200")
    d.text("t-rel", 640, 160, "deploys; supplies the realm,")
    d.text("t-rel", 640, 176, "stations and instance list")
    d.edge("M420 352V380H180V420"); d.text("t-rel", 300, 372, "boot claim, org grant")
    d.edge("M600 352V380H820V420"); d.text("t-rel", 800, 356, "dials the stations; advertises", anchor="end")
    d.text("t-rel", 800, 372, "what it serves", anchor="end")
    d.edge("M460 352V420"); d.text("t-rel", 452, 386, "publishes each registration", anchor="end")
    d.edge("M540 420V352"); d.text("t-rel", 548, 386, "only a listed publisher is heard")
    d.text("t-desc", 40, 574, "Nothing is written to disk: the directory is soft state, empty after a restart for at most one republish interval,")
    d.text("t-desc", 40, 592, "and refilled by the clients' own re-registrations and the peers' facts. A citizen registers itself and nobody else,")
    d.text("t-desc", 40, 610, "because macula verifies the caller's signature before the handler runs; a citizen_did naming anyone else is refused.")
    d.legend(650, boundary=False)
    d.write()


def components():
    d = Diagram("c4-components.svg", "mcl-citizens components", 1000, 1090)
    d.bound(16, 40, 968, 800, "mcl-citizens [Container]")
    d.box("b-mac", 32, 70, 456, 110, "mcl_om", "[library, ~> 1.4]",
          ["boot/1: loads the node identity key, joins the realm, dials the",
           "stations, registers the declared capabilities, serves /health"], code=True)
    d.box("b-mac", 512, 70, 456, 110, "macula SDK", "[library, ~> 16.0, wire 1.0]",
          ["QUIC transport, signed calls (the caller's node id, verified before",
           "the handler runs), fact topics and the node keys behind the list"], code=True)
    d.box("b-sys", 32, 210, 456, 140, "mcl_citizens_service", "[mcl_om_service behaviour]",
          ["The six callbacks mcl_om resolves by name at startup:",
           "register_presence, list_citizens and get_citizen are",
           "its own procedures; mcl_om adds info and get_limits,",
           "both open. capabilities/0 is the list. No store."], code=True)
    d.box("b-cmp", 512, 210, 456, 130, "mcl_citizens_sup", "[supervisor, rest_for_one]",
          ["citizen_directory, then hear_citizen_presence. A directory restart",
           "empties the table, and the listener restarts behind it so nothing is",
           "admitted into a table that is about to vanish"], code=True)
    d.box("b-sys", 32, 370, 456, 140, "register_presence_responder", "[macula_response RPC provider]",
          ["handle_request/2 reads the caller macula verified and refuses a",
           "citizen_did that names anyone else; bounds ttl_ms to 20 min, stamps",
           "registered_at from this instance's clock, writes through the one",
           "policy, then publishes the registration"], code=True)
    d.box("b-cmp", 512, 370, 456, 140, "hear_citizen_presence", "[gen_server, federation listener]",
          ["Subscribes to citizen_presence_registered_v1. A fact is taken only",
           "when macula verified its publisher and the node id is in",
           "MCL_CITIZENS_PRESENCE_PUBLISHERS. Re-subscribes every 5 s while the",
           "mesh is dark and counts what it drops, logged once a minute"], code=True)
    d.box("b-cmp", 32, 534, 456, 140, "mcl_citizens_facts + citizen_did", "[topics and the citizen id]",
          ["presence_topic/1: <realm>/mcl-citizens/citizens/directory/",
           "citizen_presence_registered_v1. Checks sha256(MCL_REALM_NAME) ==",
           "MCL_REALM at start. citizen_did parses and hex-encodes a DID, so a",
           "raw 32-byte id never reaches a reply or a fact"], code=True)
    d.box("b-sys", 512, 534, 456, 140, "on_citizen_presence_maybe_admit", "[the one admission policy]",
          ["One code path for an own registration and a federated fact. Expiry",
           "is registered_at + ttl_ms, capped at 20 min from this clock; a stamp",
           "60 s ahead is refused. The latest registered_at wins, and an older",
           "replay replaces nothing"], code=True)
    d.box("b-cmp", 32, 698, 456, 120, "list_citizens + get_citizen responders", "[macula_response RPC providers]",
          ["list_citizens answers every live entry; get_citizen takes a 64-hex",
           "citizen_did. Both read the ETS table directly, and an expired",
           "entry is invisible at read time"], code=True)
    d.box("b-cmp", 512, 698, 456, 120, "citizen_directory", "[gen_server over ETS]",
          ["Every write goes through admit/2, which compares against the live",
           "entry and decides, so two registrations cannot both win. sweep/0",
           "removes expired entries every 60 s, keeping memory bounded"], code=True)
    d.box("b-ext", 32, 870, 936, 108, "host environment", "[environment, from the host; the container holds only the identity key]",
          ["MCL_REALM, MCL_REALM_KEY, MACULA_STATION_SEEDS, MACULA_STATION_NODE_IDS, MCL_CITIZENS_PRESENCE_PUBLISHERS,",
           "MCL_REALM_NAME and the boot claim's MCL_SERVICE_NAME and MCL_BOX. deploy/docker-compose.yml refuses to start without the required ones"])
    d.edge("M488 125H512"); d.text("t-rel", 500, 62, "calls", anchor="middle")
    d.edge("M260 180V210"); d.text("t-rel", 268, 204, "boots through mcl_om:boot/1")
    d.edge("M488 275H512"); d.text("t-rel", 500, 268, "starts", anchor="middle", rotate=-90)
    d.edge("M740 340V370"); d.text("t-rel", 748, 364, "supervises")
    d.edge("M260 510V534"); d.text("t-rel", 268, 528, "publishes each registration")
    d.edge("M740 510V534"); d.text("t-rel", 748, 528, "a listed instance only")
    d.edge("M488 440H500V604H512"); d.text("t-rel", 506, 524, "hands it over")
    d.edge("M740 674V698"); d.text("t-rel", 748, 692, "admit/2, one writer")
    d.edge("M488 758H512"); d.text("t-rel", 500, 690, "reads the directory", anchor="middle")
    d.text("t-desc", 40, 1006, "config/sys.config.src fixes the org, mcl-citizens, which prefixes its own procedures; it also pins the realm key.")
    d.text("t-desc", 40, 1022, "deploy/docker-compose.yml mounts only the identity volume: nothing here writes to disk, so there is no data volume to lose.")
    d.legend(1052, boundary=False)
    d.write()


if __name__ == "__main__":
    for make in (context, components):
        make()
