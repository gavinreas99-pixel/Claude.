"""Packs src/JadeJungleGoblins into JadeJungleGoblins.rbxmx (a Studio model file).

Run:  python3 tools/build_rbxmx.py
Then drag the .rbxmx into Studio's ReplicatedStorage.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src" / "JadeJungleGoblins"
OUT = ROOT / "JadeJungleGoblins.rbxmx"

# (file, instance name, class, RunContext) — RunContext: 1 = Server, 2 = Client
ITEMS = [
    ("Config.luau", "Config", "ModuleScript", None),
    ("GoblinBuilder.luau", "GoblinBuilder", "ModuleScript", None),
    ("GoblinAnimator.luau", "GoblinAnimator", "ModuleScript", None),
    ("GoblinSpawner.server.luau", "GoblinSpawner", "Script", 1),
    ("GoblinAnimate.client.luau", "GoblinAnimate", "Script", 2),
]


def cdata(text):
    # "]]>" can't appear inside CDATA; split it across two sections if it ever does.
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def main():
    parts = [
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">',
        '\t<Item class="Folder" referent="RBX0">',
        '\t\t<Properties><string name="Name">JadeJungleGoblins</string></Properties>',
    ]
    for i, (file, name, cls, run_context) in enumerate(ITEMS, start=1):
        source = (SRC / file).read_text()
        parts.append(f'\t\t<Item class="{cls}" referent="RBX{i}">')
        parts.append("\t\t\t<Properties>")
        parts.append(f'\t\t\t\t<string name="Name">{name}</string>')
        if run_context is not None:
            parts.append(f'\t\t\t\t<token name="RunContext">{run_context}</token>')
        parts.append(f'\t\t\t\t<ProtectedString name="Source">{cdata(source)}</ProtectedString>')
        parts.append("\t\t\t</Properties>")
        parts.append("\t\t</Item>")
    parts.append("\t</Item>")
    parts.append("</roblox>")
    OUT.write_text("\n".join(parts) + "\n")
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
