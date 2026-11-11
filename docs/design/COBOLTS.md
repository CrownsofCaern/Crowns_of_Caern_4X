# Cobolts — neutral trader faction proposal

Status: implemented first gameplay pass, 2026-11-09. Approved design with a 40% resource exchange discount. Concept-matched production still sprites are included; animations remain the next production pass.

## Core experience

A useful bargain behind closed canvas. Every post offers reliable commercial information and deliberately unreliable military information. Trade preserves a useful stop; robbery exchanges that future value for a risky immediate payout.

Cobolts are non-playable: no starting faction, heroes, town tree or conquest ownership. Their five-tier roster supplies recruits and defenders. Keep the spelling **cobolts**.

## Posts and offers

Three commercial levels: Roadside Stall, Caravan Yard, Vault Exchange. Each has exactly three offer slots:

1. One cobolt creature type selected from the five-tier roster, with a finite recruit pool. Players choose quantity, not a different tier.
2. One specific artefact, one copy.
3. One fixed directional resource exchange, such as wood → ore, with a displayed bundle size and finite uses. No reverse exchange or other resource choices.

Approved offer structure: “one of the 5 tiers” means one locally available creature type, rather than all five types in every post. “Only one specific trade” refers to the resource exchange; hiring and the artefact remain separate offers.

| Post | Recruit eligibility | Artefact ceiling | Resource bundle stock |
|---|---|---|---|
| L1 Roadside Stall | T1–T2 | Minor | Small |
| L2 Caravan Yard | T1–T4 | Major | Medium |
| L3 Vault Exchange | T2–T5 | Relic | Large |

Higher levels improve stock potential, not guaranteed army strength. Use overlapping defender distributions: a stall can conceal veterans, and a wealthy exchange can have a depleted escort. No level-specific minimum or maximum guard count in UI.

The resource exchange costs 40% less input than the existing one-market exchange for identical output. This checkout has no separate trade-camp rule, so one market is the explicit fixed baseline. Bundles deliver eight resource units, permitting exact whole-number discounts for every pair under the current economy. Recruitment starts at normal unit prices and artefacts at normal values: scarcity already gives the post a distinct role. The discount is specifically on resource exchange.

Roll stock and defenders once at map creation or authored-site initialization. Purchases persist across visits and saves. Weekly restock replenishes the same creature and same exchange up to a cap; unbought stock never accumulates without limit. Artefacts do not restock in the first version. Never reroll by reopening the panel or loading a save.

## Five recruit tiers

| Tier | Working name | Combat role / first ability direction |
|---|---|---|
| 1 | Pack Runner | Cheap fast infantry; first-strike candidate |
| 2 | Caravan Spear | Defensive infantry; anti-charge candidate |
| 3 | Bolt Broker | Fragile crossbow ranged unit; armour-piercing candidate |
| 4 | Cinder Alchemist | Ranged support; limited fire-pot splash candidate |
| 5 | Vault Warden | Heavy shield infantry; protection/taunt candidate |

Abilities are concepts, subject to existing combat support and balance. Five tiers do not imply parity with the playable factions' eight-tier endgame armies. First version has no upgrades, new combat subsystem, or post combat bonuses. Bought recruits join ordinary army stacks and reveal their own normal stats; they do not reveal the site's defenders.

## Guard secrecy

Without scouting: show **“Guards concealed”** only. No count, count word, unit list, strength adjective, matchup verdict, odds, skull rating or guard-derived reward hint. Trade visits and purchases reveal nothing about defenders.

With scouting: show an explicitly uncertain report, for example **“At least one spear patrol. Rough estimate: 20–45 visible guards. Reserves unknown.”** Reports describe observed roles and wide estimated counts; they never give exact totals, an exhaustive roster or win probabilities. Concealed reserves mean the displayed interval is an observation estimate, not a guaranteed total bound. Clearly label this in the report.

Scouting pays the existing movement cost and uses existing range and skill rules. Better Scouting reduces cost and improves observed role detail; even mastery never removes uncertainty. Reports belong to the scouting player and last one day, matching existing scouting lifetime. Repeat inspection within the day returns the same report. Future reports can improve role coverage but should not provide independent noisy numbers that can be averaged into an exact total.

The stored army stays fixed until actual combat changes it. No extra troops are generated in response to the attacker's strength or after a robbery decision. Concealment ends when battle begins and the normal battlefield reveals the forces.

Secrecy must apply to map hover, site panel, pre-battle confirmation, combat predictor, tooltips, accessibility text and AI evaluation. Sanitize the intel payload before it reaches these consumers; hiding labels alone is insufficient. AI decisions use the same observations rather than the private garrison. Save files can contain authoritative armies; this is gameplay secrecy, not anti-file-inspection security.

## Trade or rob

Interaction offers **Trade**, **Scout** and **Rob**. Rob opens a commitment panel with known consequences and the current uncertain report. It never opens the ordinary exact battle forecast. Cancel before committing has no consequence.

Committing to robbery starts combat and marks this player hostile to that post immediately. Losing or retreating leaves the post closed to that player; other players can still trade. The surviving garrison persists using normal combat outcomes. Keep consequences local in the first version so one decision does not silently disable every post on the map.

Winning yields a fixed loot cache rolled with the post, plus its unsold artefact if present. No purchased artefact duplicates, no automatic addition of all defender units as recruits, and no conversion of infinite weekly stock into loot. Previously bought goods reduce remaining sale stock normally; the fixed robbery cache prevents emptying a shop and then looting its full original inventory again. Tune total trade-then-rob profit against the cost of the battle.

A defeated post becomes a persistent **Plundered Post**: no trade, recruits or restocks for anyone; no capturable income. Its ruin remains on the map. Successful robbery therefore destroys future economic value for every player. State this explicitly before commitment.

## Presentation and later animation

Art direction: small wiry reptilian humanoids; narrow snouts, modest swept horns, dull rust/slate scales, layered merchant cloth, brass seals and practical equipment. Grim, wary and capable. No comic mascot proportions. Trade posts use closed awnings, covered yards and shutters so architecture supports the uncertainty mechanic. Wealth reads through materials and storage, not a visible troop count.

First concept board: five recruit silhouettes and three commercial post levels. It is reference artwork, not a usable sprite sheet. Review species identity, tier progression and post shapes before making production assets.

Next artwork pass: individual unit views, then neutral idle/walk/attack/hit/death animations fitted to the existing animation pipeline. Posts need lantern flicker, canvas movement, trade activity and a plundered variant. Background activity must not encode the hidden garrison count. Confirm facings, frame counts and native sizes from current production specs before drawing sheets.

## Implementation order and acceptance

1. Neutral roster/site schema separate from playable-faction setup and eight-tier roster validation.
2. Persistent stock, garrison, robbery cache, player-local hostility and plundered state.
3. Shared masked intel policy and cobolt-specific uncertain scouting reports.
4. Trade panel, commitment flow, combat resolution and map generation/editor support.
5. Production artwork and animations after the concept direction is accepted.

Acceptance checks: unscouted guards never leak; mastery stays uncertain; AI respects secrecy; preview cannot expose odds; reports are stable and expire correctly; stock and garrisons survive save/load; buying cannot duplicate loot; failed robbery closes only the local player's access; a plundered post never restocks; non-playable cobolts never appear in faction selection.
