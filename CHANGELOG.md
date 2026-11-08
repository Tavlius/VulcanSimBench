# Changelog

## v1.2.2 - The Sim button, and talents read on two nodes

- **The Sim button is visible again** on Forever's Character panel: it sat under the row of
  sidebar tabs at the panel's top right, and now sits just left of them.
- **No false "Missing: talents".** Forever's Hunter talent tree lists Lightning Reflexes on two
  nodes, one never ranked; 1.2.1 flagged any spell on two nodes. Now it exports the one rank,
  and flags only nodes that disagree.

## v1.2.1 - Forever's talents

- **Talents now export on Forever.** Forever's client keeps talents in the newer trait
  system, which 1.2.0 didn't read, so exports showed no talents. Ranked talents are now
  exported by spell ID (`ts`), with how many talents were read (`tsn`); the sim maps them
  onto its talent trees. Clients with the classic talent calls still export `tal`, `tr` and
  `tn` as before.
- `/simx check` counts your talent points and talents; `/simx debug` lists the trait config
  and every ranked talent, for bug reports.

## v1.2.0 - first public release

- Now **Vulcan SimBench**, part of the Vulcan Suite. `/simbench`, `/simx` and `/simexport`
  all work.
- The sim is now the **Vulcan Sim** at vulcanaddons.com/sim. Paste your export into its
  **Your character** box. `/simbench sim` and the new **Where's the sim?** button show the
  address, ready to copy.
- If the Forever client fails to load this character's saved data, SimBench says so.
- Exports carry the add-on's release version (or "dev" from source).
- Frame accent in the Vulcan Suite's ember orange.

## 1.1 (as SimExport)

- Set bonuses: plain-stat bonuses are added (`sb`), the rest listed by set and bonus
  number (`sbx`). "Equip:" stats the game's item stats leave out are read from the tooltip
  (`ie`). Talents read through `C_SpecializationInfo`, with tree totals exported when the
  game gives nothing per talent. `/simx verify` opens a paste box. Items that hadn't loaded
  are reported and requested. The decoder rejects malformed or hostile values.

## 1.0 (as SimExport)

- First version.
