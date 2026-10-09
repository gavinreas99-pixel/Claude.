# Jade Jungle Goblins

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
