# Vulcan SimBench

An add-on for **World of Warcraft: Forever** that copies your gear, talents and stats as one line of text, for the **Vulcan Sim** at [vulcanaddons.com/sim](https://vulcanaddons.com/sim).

The sim ranks every class and talent tree by damage against players or a raid boss, and plays out 1v1 duels. Paste your string into its **Your character** box and it uses your real gear for your class.

**Display only, no automation.** The add-on reads your character out of combat and shows a box of text. It never casts, targets, moves or clicks anything for you, and it sends nothing to anyone. WoW add-ons can't reach the internet: the string only goes where you paste it.

Part of the **Vulcan Suite**: Vulcan GrindWatch · Vulcan RunBook · Vulcan DuoQuest.

## Install

- **CurseForge app** or **WowUp**: search for *Vulcan SimBench* and install it for World of Warcraft: Forever.
- **By hand**: unzip the download and copy the `VulcanSimBench` folder into the `Interface\AddOns\` folder of your Forever game folder (Battle.net > the Forever game > gear icon > *Show in Explorer*, or *Show in Finder* on a Mac).

At the character screen, click **AddOns** and make sure Vulcan SimBench is ticked. If it's greyed out as "out of date", tick **Load out of date AddOns**.

## Use

1. **Open the sim** at [vulcanaddons.com/sim](https://vulcanaddons.com/sim) in any web browser. WoW can't open a web page itself; `/simbench sim` (or **Where's the sim?** in the export window) shows the address in a box you can copy.
2. **Export your character.** Out of combat, type `/simbench` (or click the **Sim** button on the Character panel, SimBench in the add-on menu by the minimap, or a key you bind under Options > Key Bindings > AddOns > Vulcan SimBench). A box opens with the string selected. Press **Ctrl+C** (**Cmd+C** on a Mac).
3. **Paste it into the sim**, in its **Your character** box.

Any notes (for example "Found your quiver but couldn't read its haste") appear under the string in game. The string has a checksum, so a copy that got cut off is rejected instead of misread. Sharing a string on Discord? Put it in a code block (wrap it in backticks), so Discord doesn't turn parts of it into emoji.

`/simbench`, `/simx` and `/simexport` all work.

| Command | What it does |
| --- | --- |
| `/simx` (or `/simx export`) | Export (out of combat) |
| `/simx sim` | The sim's web address, in a box you can copy |
| `/simx last` | Show this character's last export again |
| `/simx check` | What your client supports and what an export reads right now (talents, weapons, sets, stat totals), and whether your saved data loaded |
| `/simx items` | Raw stats of each equipped item, for checking stat names |
| `/simx verify` | Opens a box: paste a string to check it's complete |
| `/simx button` | Show or hide the Character-panel button |
| `/simx debug` | Raw game data (talent, item, tooltip and stat API returns), to attach to a bug report |

**Format versions.** The add-on and the sim match on the string's format (`FSX1` today), not on version numbers. If you paste a string from an older SimBench, the sim tells you to update the add-on and export again, instead of showing wrong numbers.

## What's in the string

Class, race, level, client build, date, talent points and ranks per tree, equipped item IDs and enchant IDs, weapon damage and speed, ammo damage, quiver haste, summed item stats (including plain stats that only appear as "Equip:" text), active set bonuses, your character-sheet numbers, and your active buff IDs. **Not** included: your name, realm, guild, or anything about other players.

## Why combat is blocked

Forever uses the same add-on rules as Midnight: during combat, stats come back as "secret values" add-ons can't read. Export between pulls.

## Known Forever client issue: saved data

The Forever beta client has been reported to write add-on data to disk but sometimes fail to load it back, and then overwrite the good file the next time you log out or /reload. SimBench keeps only your last export and the button setting per character. It also keeps a small account-wide file that only lists which characters have saved data.

- **It notices a failed load.** If a character on that list comes back with no saved data, SimBench warns you in chat instead of quietly starting empty. Exporting again is usually all you need. If both files fail at once, that looks like a fresh install and can't be detected.
- **Backing up by hand:** with the game closed, copy the `WTF` folder in your Forever game folder. SimBench's file is `WTF\Account\<account>\<realm>\<character>\SavedVariables\VulcanSimBench.lua`.

Community workaround tools exist. SimBench doesn't need or rely on any of them, and some work by editing add-on files that your add-on updater replaces.

## Limits

- Enchants are listed by ID; the sim leaves them out.
- Set bonuses are read from your set pieces' tooltips. Plain-stat bonuses (+40 Attack Power, +1% hit, +8 all resistances) are counted. Procs, ability changes and conditional bonuses ("when fighting Undead") are listed by number for the sim; they're never guessed into the stat totals. Stat wording is matched in English plus the client's own strings for the main stats, so other bonuses on non-English clients are listed by number.
- Talents are read from your active spec. If the game only gives points per tree, those are exported and you pick the talents in the sim. Export again after switching specs.
- Right after logging in, some items may not have loaded yet. The export says which, and asks the game to load them, so exporting again a few seconds later works.
- The sim models level 60, and the export notes say so for a lower-level character.

## Format (for developers)

```
FSX1:key=value;key=value;...#adler32
```

One ASCII line (UTF-8 if tree names are localized). Lists use `,`, sub-fields `:`. The checksum is Adler-32 of everything before `#`, as 8 lowercase hex digits. Whitespace is never part of the string, so decoders strip it before checking. `FSX1` is the format version: bump it in `Util.lua` (`ns.FORMAT`) whenever the layout changes (`tests/tests_format_contract.lua` has the checklist).

| Key | Meaning | Example |
| --- | --- | --- |
| `v` | Add-on version (`dev` when run from source) | `1.2.0` |
| `b` | Client version and build | `1.60.1.70009` |
| `d` | Export date (your computer's local date) | `2026-10-01` |
| `cls`, `race`, `lvl` | Class file, race file, level | `HUNTER`, `Human`, `60` |
| `fac` | Faction (tells the two Skyborne races apart) | `Alliance` |
| `tal` | Points per tree | `31-20-0` |
| `tr` | Ranks per talent, by tier then column, per tree; absent if the client only gives tree totals | `0505...-3500...-0` |
| `tn` | Tree names (spaces as `+`) | `Beast+Mastery,...` |
| `g` | `slot:itemID:enchantID[:loc]` (slot 0 = ammo; loc on 16-18) | `16:12784:1900:2H` |
| `w` | `slot:min:max:speed[:loc]` weapon base damage | `18:82:124:3.3:RG` |
| `ammo` | Ammo damage per second | `17.5` |
| `qv` | Quiver ranged haste, percent | `15` |
| `set` | `setID:pieces` for equipped set items | `515:3` |
| `sb` | Active set-bonus stats, summed (same keys as `is`) | `AP:40,HIT:1` |
| `sbx` | Active set bonuses that aren't plain stats, as `setID:bonus#` | `515:2` |
| `is` | Summed item stats (`AGI`, `CRIT` %, `ARMOR`, ...) | `AGI:31,CRIT:1` |
| `ie` | The part of `is` read from "Equip:" text | `HIT:1` |
| `sh` | Character sheet, buffed | `ap:700,crit:12.3` |
| `bs` | Character sheet minus the game's "bonus" part | `agi:240,ap:600` |
| `au` | Active buff spell IDs | `1126,27681` |
| `miss` | What couldn't be read | `weapon18,quiver` |

A reader should find the string inside any pasted text, check the checksum, accept only well-formed values, and escape all text before putting it in a page.

## Development

The repository is the add-on folder:

- `*.lua`, `Bindings.xml`, `VulcanSimBench.toc`: the add-on.
- `tests/`: the Lua tests and every check, run by `tests/run.sh`. The Lua tests also write sample exports (for every class, a paste corpus, a set-bonus sample) that the sim's own tests use.

The sim itself isn't in this repository.

Run everything in the pinned container, from Git Bash or any shell with Docker:

    sh tests/docker.sh

After cloning (or right after `git init`), run this once before the first commit, from Git Bash on Windows (PowerShell has no `sh`). It sets this repository's commit identity and installs a pre-push hook that runs the personal-data guard over the tree and the whole history:

    sh tests/init_repo.sh

Commits must carry a GitHub noreply email address (`<id>+<username>` at `users.noreply.github.com`); the guard refuses any other address.

That covers: luacheck, the Lua suites in both tooltip modes, the personal-data guard, and a real package build. The GitHub Actions workflow runs exactly the same container. Pushing a tag `vX.Y.Z` packages the add-on with the BigWigs packager and uploads it to CurseForge and Wago (the tag needs a matching `## vX.Y.Z` section in `CHANGELOG.md`).

The export format is a contract with the sim. `tests/tests_format_contract.lua` pins it, so a layout change fails CI until `ns.FORMAT` is bumped, the contract is updated, and the sim's maintainers are told (they refresh their sample exports from this add-on).

- **Client version:** `## Interface: 16001` matches Forever 1.60.1. When the Forever client version changes, bump it in `VulcanSimBench.toc` and in `tests/tests_release.lua`.
- **Version:** the TOC's `## Version:` line holds the packager's version token (`project-version` between two `@` signs), and the packager replaces it with the tag. The add-on shows it and puts it in exports (`v1.2.0` as `1.2.0`, or `dev` from source). The sim matches strings by format, never by version.
- **The sim's address** is `ns.SIM_URL` in `UI.lua`.
- **Retiring the saved-data safety layer** once Blizzard fixes the client: delete `Persist.lua`, its TOC line, the `## SavedVariables: VulcanSimBenchDB` line and `tests/tests_persist.lua`. Then remove the marker check in `tests/tests_static.lua` and the "Known Forever client issue" section here. Commands.lua only reaches the module through `ns.Persist` checks.

## License

MIT. See [LICENSE](LICENSE). Changes are listed in [CHANGELOG.md](CHANGELOG.md).
