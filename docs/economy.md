# Economy

A baseline for tuning prices. Income comes from `tests/sim/balance_sim.tscn`
(120 full runs per profile; it prints an "income per run" line for each), so
re-run it after changing rewards or costs and update the tables.

## Income per run (sim, Sep 2026)

| Profile | Clear rate | Coins | Crystals | Seal Tokens | Loot (sale value) |
|---|---|---|---|---|---|
| Lesser — new player (2 F heroes, Lv1) | ~28% | 132 | 41 | 3 | 63 |
| Lesser — invested (3 heroes, Lv4) | 100% | 170 | 53 | 10 | 68 |
| Greater — underleveled | ~23% | 337 | 97 | 4 | 77 |
| Greater — invested (4 heroes, Lv7) | 100% | 418 | 118 | 18 | 80 |
| Endless — endgame, per attempt (~5 cycles) | — | 5,284 | 1,312 | — | 346 |

A failed run still pays for every fight it won, so newcomers earn most of an
invested party's coins. Endless rewards grow +20% per cycle (foes +50%), so an
attempt is worth about 3× a Greater run of the same length.

## Sinks

| Currency | Sink | Cost |
|---|---|---|
| Coins | Recruit a hero | F 25 · E 45 · D 75 · C 130 · B 220 · A 380 · S 650 |
| | Reroll a recruit / Champion offers | 20 / 60 |
| | Train an attribute point | 50 × n, up to 8 per hero (1,800 per hero) |
| | Skill respec | 20 + 10 per SP spent |
| | Trait reroll | 60 |
| | Field Tonic · Incense · Runestone | 25 · 40 · 60 |
| | Shop item/relic | ~25–40, reroll 8 + 6 per reroll |
| Crystals | Guild Management levels | ~4,150 for every level |
| | Management capstones | 350–400 each |
| | Relic upgrade to Lv5 | 15 × rarity mult × level per step (epic ≈ 285) |
| | Relic effect reroll / item reforge | 10 × mult × n / 8 × mult × n |
| Seal Tokens | Attribute reset | 5 × hero level |
| Evolution Stones | Evolution, Stonebound skill node | 1 each |

## Target curve

- **First session (runs 1–3):** hire a second and third hero (D-rank after one
  run), a few Management levels, first relic.
- **Act I → II (runs 5–15):** a full roster, first Management capstone,
  relics climbing to Lv3.
- **Act II → III (runs 15–40):** training heroes toward the 8-point cap,
  epic relics to Lv5, most Management branches.
- **Post-campaign:** Endless and quests fund the remaining capstones and
  rerolls; coins keep a use through training and recruits for new heroes.

## Watch list

- Coins outpace sinks once the roster is full; training (1,800 per hero) is
  the main mid-game sink. If coins still pile up, the next lever is recruit
  prices for C+ ranks or a coin cost on relic upgrades.
- Seal Tokens have one sink (attribute resets); fine while they're earned
  slowly, revisit if players sit on hundreds.
