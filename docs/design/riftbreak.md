# Riftbreak: breaches and base defense

Decided with the user on 2026-09-29. Brings back the Riftbreak (cut in 0.9 with
the Rift Map) as a timed event that ends in a tower-defense fight.

## The loop

1. **A rift swells.** From Act II (Act I done), a breach appears every
   `BREACH_EVERY` days after the last one was dealt with: a ladder rank, a
   region, and a countdown of `BREACH_WARN` days. Days pass as they do today
   (a rift run, a rest, an Endless run).
2. **Prevent it** by sealing a ladder rift of that rank or higher before the
   countdown ends: the breach closes, with a small bonus.
3. **Or it breaks.** Normal rift runs and the Endless Rift are blocked until the
   guild defends. The Rift Hall shows "Defend".
4. **Defend** in a tower-defense fight, then take the result.

Ranks S and up break at **the camp** itself; lower ranks break out in a
**region** (Vale, Marshes, Ashen), each with its own map.

## The defense (Kingdom Rush style)

- Monsters from the breach's region walk fixed paths toward the goal (the
  outpost, or the Guild Hall at camp). Every foe that gets through costs
  **integrity**; bosses cost more. Integrity 0 = the defense is lost.
- **Towers** go on fixed **pads**: easy on touch, and in keeping with the
  hub-scene style.
  - Ballista: single target, long range.
  - Fire Brazier: area damage, burns.
  - Frost Totem: slows.
  - Ward Stone: shields nearby heroes.
  - Chapel: heals nearby heroes.

  Each has 3 tiers. Towers are built and upgraded during the fight with
  **supplies**: a starting budget plus supplies for each kill.
- **Stationed heroes**: idle roster heroes (not wounded, busy or in a rift)
  stand at **posts** and fight with their role's attack. They can fall; fallen
  heroes come back wounded.
- **One champion** (optional) is steered by tapping or clicking where to go,
  and fires their signature on its timer (reuses the Endless Rift's signature
  code).
- Waves announce themselves. There is a short build phase before each wave,
  and "Call early" skips it for bonus supplies.

## The economy (hybrid)

- **Guild research: a new Defenses branch** in Guild Management, paid in Gold.
  This is the new Gold sink.
  - Armory: unlocks tower types.
  - Engineering: tower tier caps, cheaper builds.
  - Palisade: integrity, starting supplies.
  - Watchtower: +1 day of warning, +1 hero post.
- Supplies are earned and spent inside a fight only.

## The stakes

| Result | What happens |
|---|---|
| Held (integrity left) | Gold and Essence by rank, scaled by the integrity kept |
| Lost | 1-2 **damaged buildings** (a Guild Management upgrade works 1 level lower until repaired with Gold); a share of stored Essence and of the Gold above the coming payday's bill lost (wages are never at risk); posted heroes who fell come back wounded |

Never game over.

## Build phases

- **A. Countdown and stakes (logic).** Breach state, the days tick, prevention
  by sealing, blocking runs when broken, and the resolution: rewards, damaged
  buildings (`lvl()` minus damage) and repairs. Tested headless.
- **B. The defense simulation.** `DefenseRun`: a pure simulation like
  `SurvivorsRun` (paths, waves, towers, posts, champion, supplies, integrity),
  tested headless and tuned with a `balance_sim -- defense` mode.
- **C. The defense screen and research.** `DefenseView`, the camp and Rift
  Hall entry points, the Defenses research branch, and Turkish text.
- **D. Art.** 3 region maps and a camp map, 5 towers × 3 tiers, done with
  PixelLab.
