# Jade Jungle Goblins & Quest-style UI

This repo has two drop-in packages:

- **`JadeJungleGoblins.rbxmx`** adds animated goblin enemies (see below).
- **`QuestThemeUI.rbxmx`** restyles your Bag and Tutorial screens to look like the Quests window (see [Quest-style UI](#quest-style-ui)).

## Jade Jungle Goblins

Goblin enemies for the Jade Jungle. They're modeled on the classic big-eared goblin: big bald head, angry brows, droopy nose, long ears, red tunic with leather belts, a spiked round shield and a curved scimitar. Each goblin has a real jointed rig, so it runs, swings its sword and flinches instead of sliding around like a block.

![preview](docs/preview.png)

*Top: rest pose, idle stance, sword windup, slash. Bottom: one full running stride.*

## What they do

- **Run animation.** A full stride with knee tuck and toe push-off. The body bobs and leans into the run, hips and shoulders twist, and arms swing opposite the legs. The ears and loincloth flop with each step. At wandering speed it slows into a walk.
- **Idle animation.** A crouched, breathing stance with the sword raised. The goblin looks around and its ears twitch.
- **Combat.** Goblins chase players who come near and do an overhead sword slash, which deals damage when the blade lands. They flinch when hit.
- **Death.** The goblin goes limp as a ragdoll, then respawns at its spawn point later.
- **Variety.** Every goblin gets slightly different skin and tunic colours.

The animation runs on each player's computer, so it's smooth and doesn't load the server.

## Install (easiest way)

1. Download `JadeJungleGoblins.rbxmx` from this repo.
2. In Roblox Studio, drag the file into **ReplicatedStorage**. The folder must be in ReplicatedStorage; the scripts inside are set to run from there.
3. Add spawn points:
   - In **Workspace**, make a Folder named `JadeJungle`. Inside it, make a Folder named `GoblinSpawns`.
   - Put Parts in `GoblinSpawns` where the goblins should live. Make them anchored, and set Transparency to 1 and CanCollide to off. Each Part gets one goblin.
   - If you skip this step, 6 goblins spawn around position (0, 10, 0) and a warning appears in Output.
4. Press **Play**.

**Remove your old block entities** (or the script that spawns them) so they don't run alongside these.

## Settings

Open `JadeJungleGoblins > Config` to change:

| Setting | What it does |
| --- | --- |
| `Scale` | Goblin size (1.1 ≈ a bit shorter than a player) |
| `MaxHealth`, `AttackDamage`, `AttackCooldown` | How tough and dangerous goblins are |
| `WanderSpeed`, `ChaseSpeed` | Movement speed |
| `AggroRange`, `LeashRange`, `WanderRadius` | How far they notice players, chase them and roam |
| `RespawnTime`, `MaxGoblins`, `GoblinsPerSpawn` | Population |

## Files

All files are in `src/JadeJungleGoblins/`:

- `GoblinBuilder.luau` builds the goblin model and its 17-joint rig.
- `GoblinAnimator.luau` contains the procedural run, idle, attack and flinch animation.
- `GoblinAnimate.client.luau` animates every goblin on each player's screen.
- `GoblinSpawner.server.luau` handles spawning, AI, damage, ragdolls and respawning.
- `Config.luau` holds the settings above.

If you edit the source files, rebuild the Studio file with `python3 tools/build_rbxmx.py`. Rojo users can `rojo serve` the included `default.project.json` instead (Rojo 7.4+).

## Want it even more realistic?

These goblins are built from smooth rounded parts, so they look like the reference picture but not like a sculpted, textured model. To get a photo-quality look, import a goblin **MeshPart** model (from Blender or the Toolbox) and name its joints like this rig's. The animation code drives any model with the same joint names: `Root`, `Waist`, `Neck`, `Left/RightShoulder`, `Left/RightElbow`, `Left/RightHip`, `Left/RightKnee`, `Left/RightAnkle`, `Left/RightEar`, `FrontFlap`, `BackFlap`.

## Quest-style UI

`QuestThemeUI.rbxmx` gives your **Bag** and **Tutorial** screens the look of the Quests window:

- dark navy window with a red border and a red gradient title bar
- dark blue cards and near-black item slots
- dark tab and action buttons
- rounded progress bars
- bold white text, grey descriptions, yellow XP and a red close X

![UI theme preview](docs/ui-theme-preview.png)

*Example run on mock Bag and Tutorial screens: before on the left, after on the right.*

**Install:** drag `QuestThemeUI.rbxmx` into **ReplicatedStorage** and press Play.

**How it works:** when the game runs, the script finds every ScreenGui whose name contains `bag`, `inventory`, `backpack` or `tutorial`. It restyles whatever is inside: colours, fonts, outlines, gradients and rounded corners. It never moves or resizes anything, so your layout and your own scripts keep working. Items added to the bag later get styled automatically.

- **Your screens are named differently?** Edit the `TARGET_GUIS` list at the top of the `ApplyQuestTheme` script.
- **Want to keep one element exactly as it was?** Give it the attribute `NoTheme` = `true`.
- **Changes only show in Play mode,** not while you're editing in Studio.
