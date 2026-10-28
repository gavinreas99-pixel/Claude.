"""Packs the folders in src/ into .rbxmx Studio model files.

Run:  python3 tools/build_rbxmx.py
Then drag each .rbxmx into Studio's ReplicatedStorage.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# package name -> [(file, instance name, class, RunContext)]; RunContext: 1 = Server, 2 = Client
PACKAGES = {
    "BugCatcher": [
        ("Config.luau", "Config", "ModuleScript", None),
        ("Util.luau", "Util", "ModuleScript", None),
        ("Environment.luau", "Environment", "ModuleScript", None),
        ("BugData.luau", "BugData", "ModuleScript", None),
        ("BugBuilder.luau", "BugBuilder", "ModuleScript", None),
        ("FieldBuilder.luau", "FieldBuilder", "ModuleScript", None),
        ("WorldServer.server.luau", "WorldServer", "Script", 1),
        ("WorldClient.client.luau", "WorldClient", "Script", 2),
        ("BugServer.server.luau", "BugServer", "Script", 1),
        ("BugVisuals.client.luau", "BugVisuals", "Script", 2),
    ],
    "JadeJungleGoblins": [
        ("Config.luau", "Config", "ModuleScript", None),
        ("GoblinBuilder.luau", "GoblinBuilder", "ModuleScript", None),
        ("GoblinAnimator.luau", "GoblinAnimator", "ModuleScript", None),
        ("GoblinSpawner.server.luau", "GoblinSpawner", "Script", 1),
        ("GoblinAnimate.client.luau", "GoblinAnimate", "Script", 2),
    ],
    "QuestThemeUI": [
        ("ApplyQuestTheme.client.luau", "ApplyQuestTheme", "Script", 2),
    ],
    "RealisticPistol": [
        ("Config.luau", "Config", "ModuleScript", None),
        ("GunBuilder.luau", "GunBuilder", "ModuleScript", None),
        ("PistolServer.server.luau", "PistolServer", "Script", 1),
        ("PistolClient.client.luau", "PistolClient", "Script", 2),
    ],
}


def cdata(text):
    # "]]>" can't appear inside CDATA; split it across two sections if it ever does.
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def build(package, items):
    src = ROOT / "src" / package
    out = ROOT / f"{package}.rbxmx"
    parts = [
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">',
        '\t<Item class="Folder" referent="RBX0">',
        f'\t\t<Properties><string name="Name">{package}</string></Properties>',
    ]
    for i, (file, name, cls, run_context) in enumerate(items, start=1):
        source = (src / file).read_text()
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
    out.write_text("\n".join(parts) + "\n")
    print(f"wrote {out.relative_to(ROOT)}")


def main():
    for package, items in PACKAGES.items():
        build(package, items)


if __name__ == "__main__":
    main()
