# Crowns of Caern: story bible

The canonical account of the world, its peoples and the eight campaigns. `data/campaigns.json` holds the
text the player reads; this file holds what the writers must keep straight. The six-campaign
arc was approved on 2026-11-07 (an earlier draft). The 2026-11-09 story edit (this file) tightened the six campaigns,
named every antagonist, and added the two expansion campaigns.

Rules for anyone touching story text:

- Names, places and events are original. Nothing from Heroes of Might and Magic or any other game.
- The six main campaigns are **one war seen from six sides**. A scene that two campaigns share (the Burning
  Ford, the Iron Pass, Saint Orrin's Rest) must agree on the facts, but each side may be wrong about the
  other's reasons. Keep the shared lines word-for-word (the raider's "Your sky did this", the axe message
  "Remember who was cold first", the ledger that says only "Wider").
- Every chapter has an `intro` (briefing, two or three paragraphs, the last one says what to do and which
  tier opens), a one-line `text`, and an `outro` that ends on a turn: a fact, a doubt or a threat that the
  next chapter picks up.
- Every enemy with a name in the text is a hero on the map (`cast` with `owner: 1`, or a hero of the
  hand-made map), so the player can see who they are fighting.
- No faction is stupid and no faction is right. Everyone in this war has a reason.

## 1. The world of Caern

**Caern** is the name of the world, shared by all eight rival powers. The title *Crowns of Caern* refers to their competing claims to dominion.

Geography (`assets/specs/world_atlas.json`): the Frostmarch in the north under the Ancient Glacier; the
Sunken Forge's mountain spine in the west; the Concord Marches in the centre on the river roads, with
Greyhold at their southern edge and Highmere as the eastern fortress; the Elderwold west of Greyhold, felled
to stumps except the Last Grove; Sallowmere, the southern fens, grave-towns and barrows; the Wound in the
east, a ring of black rock around a burning chasm with two passes. The sea lies east and south of
everything. Under the land run the Underways: the Barrow Below (the dead's grave-realm), the Forge's
galleries, the Host's tunnels, and, deeper than any of them, the caverns of the Umbral Court.

### Timeline

| When | What |
|---|---|
| Before the peoples had names | The Umbral Court binds the dragon Karzhaloth under the world. Its six eyes are cut out and become the Gate-Eyes. The Court gives one to each surface people so that no single hand can ever open the Nightgate again, and withdraws below. The surface forgets; the Eyes become crown jewels and relics. |
| Every few centuries | The Ashen Host climbs out of the Wound. Each time it is driven back, never shut in. |
| About 400 years ago | The Second Burning. The city of Sarranth, the most learned people of the coast, flees into the sea behind a breathing-spell. A northern shaman, Skadric Whalebone, alters one rune of it out of envy. Sarranth's people survive as the Shoal: fish-folk, strong, long-lived and slow of mind. The surface forgets them. |
| About 300 years ago | Ysmay Vane takes the throne of Sallowmere and does not die. |
| 100 years ago | The Sealing. Five peoples (Concord, Forge, Thornwood, Frostmarch, Sallowmere's dead) shut the Host in the Wound. The Forge casts the Lockstone, the Elderwold's Heartroots grip it, the clans march their winter into the chasm to bank the fire, Sir Orrin Wren holds the gate and dies. The Umbral Court, and the Shoal, are not asked and do not come. |
| 40 years ago | The Concord stops paying the Forge for the Lockstone's upkeep. The Forge shuts its gates. The Concord begins felling the Elderwold for its foundries. |
| 30 years ago | Concord soldiers burn a Thornwood village and carry off a girl, Branwen Ashbark. She grows up as Maelis Thorne, ranger captain of Greyhold. |
| The Year of the Red Sky | The six main campaigns. The felled roots let the Lockstone crack; the dead flee the heat; the Host breaks out; ash turns the sky red and the northern summer fails. |
| The Year After | The expansion campaigns. The Host is broken but not gone. The surface peoples are exhausted, in each other's debt, and holding six old gems they do not understand. |

### The peoples

- **The Aldmere Concord** (`concord`): a dying feudal league of scarred veterans. Greyhold is a border town; the
  capital is far north. The Concord caused the war (felled the roots, stopped paying) without knowing it. Its
  campaign is about learning why nobody answers when it calls.
- **The Hollow Dominion** (`hollow`): the dead of the south, ruled from Sallowmere by the Regent Ysmay Vane.
  They are not evil. They are frightened, and a frightened army still marches. The dead cannot be charmed
  or corrupted: they have no minds to turn, which matters in the expansion.
- **The Ashen Host** (`ashen`): demons of the Wound, broken into broods by a hundred years of hunger, united by
  Skarn Ashborn. They are the fire the world was built on top of, and they want out.
- **The Thornwood Covenant** (`thornwood`): the druids and hunters of the Elderwold. They knew what the roots
  held and let the Concord cut them anyway. Their campaign is about that silence.
- **The Sunken Forge** (`forge`): the smith-clans under the western mountains. Cast the Lockstone, never paid,
  shut their gates for forty years and discovered that a mountain is not a wall.
- **The Frostmarch Clans** (`frostmarch`): the raiders of the north. A hundred years ago they carried their
  winter into the Wound; this year the ash stole their summer and nobody remembered the promise.
- **The Umbral Court** (`darkelf`, expansion): dark elves of the deep caverns, the wardens of the Nightgate.
  Severe, aristocratic, ruled by houses. They stayed below for a thousand years because that was the duty.
  House Vexmire, "the house that remembers the sky", was declared extinct long ago. It is not a house. It is
  a vow, and it has members in every house.
- **The Abyssal Shoal** (`fishmen`, expansion): what Sarranth became. Armoured, patient, forgetful. They keep
  the drowned city's vaults without being able to read them, until one of them can.

### Named heroes

| Faction | Heroes (class) | Notes |
|---|---|---|
| Concord | Sir Aldous Wren (Knight), Maelis Thorne (Ranger), Sister Edda Vey (Oracle) | Castellan Odo Brack holds Highmere; Abbess Maud Lorne leads the lantern temples; Sir Tamsin Hale, Foreman Hugh Tallow (Axeford Timber), Sexton Grue (a Concord gravedigger among the dead) are minor. |
| Hollow | Ysmay Vane (Necromancer), Sir Orrin Wren (Gravewarden), Father Corvin Mire (Blightcaller) | Vathek the Unbowed and the barrow-lords; Abbot Lisk under the Forge. |
| Ashen | Skarn Ashborn (Warlord), Ithra Sootveil (Warlock), Morvath the Kindler (Tormentor) | Vrask Gutmaw (eaten, twice), Garsh Emberclaw (brood chief), Gaul Cindermouth, Grisk Hollowbrand. |
| Thornwood | Cerrid Ashbark (Grovewarden), Neve Hollowreed (Huntmaster), Old Mother Brakka (Thornspeaker) | |
| Forge | Gunnra Sootmantle (Runesmith), Ironmarshal Dask Vell, Master Tobbin Greave (Artificer) | Bruna Kell (Ironmarshal of Stonevow). |
| Frostmarch | Ulvra Kettleborn (Thane), Bjarr Coldhand (Reaver), Seer Iska Rime (Frostcaller) | Hrodna Grimfell; Thane Orm Whaleroad of the shaman clan. |
| Umbral Court | Serane Nhalvor (Dreadmarshal), Matriarch Ulmarra (Veilseer), Rhuvel Askai (Nightstalker) | Sareth Draal of House Draal is the rival in chapter 1. |
| Abyssal Shoal | Ilo Who Reads (Deep Oracle), Thunn Reefbreaker (Tidemarshal), Sael Hookhand (Reef Hunter) | Gorrok Bluntjaw and Mother Urrh are the shoal chiefs who will not follow. |

## 2. The six main campaigns (the Year of the Red Sky)

All six run on the same tier schedule (2, 3, 3, 4, 5, 5, 6, 7, 8, 8) and all are open from the start.
Chapter 1 is small and introductory; from chapter 3 the map overhaul gives each campaign one townless
start (T), one 2v2 with an AI ally (A), one survival or mission map (S) and one betrayal (B), the rest
conquest maps (C), see `docs/MAP_EDITOR.md`.

### The Last Light (Concord)

Aldous Wren rides out against risen dead at harvest and ends the year holding the gate of the Wound as his
great-grandfather did, having learned that his own league broke the seal. Beats: barrow fields, Fen Road,
Saint Orrin's Rest (Orrin: "Go to the mountain"), the Forge's shut gates ("Pay it in your own blood"), the
Elderwold stumps (the dying druid calls Maelis "Branwen"; she does not answer to it), the clans' raid under
the red sky ("Your sky did this"), the Burning Ford, Ashes Return, Cindermaw. Ending: the gate cannot be
closed by soldiers alone; the Concord will have to ask the peoples it wronged, and pay.

### The Pale Inheritance (Hollow)

Ysmay Vane turns the dead's terror into a kingdom. Beats: Cairnholt, the barrow-lords ("We are fleeing"),
the Living Shore (Orrin reads his own name on a chapel wall), Thornwood burning the fen's edge, Twice Dead
(Orrin's body recovered from Greyhold and raised again; he asks whether the boy lived), the Lantern Siege
(the order of the Sealing in the vault), the Barrow Below (Ashen burrowers), the Hungry Fire (the burned
dead do not come back), the Leviathan, the Pale Crown. Ending: a kingdom of the dead in the south; Orrin
walks north to find Aldous.

### The Unsealing (Ashen)

Skarn Ashborn, a pit-chief with nothing, unites the broods and breaks the Lockstone. Beats: the Gnawing Pit
(Vrask eaten), Ithra reads the cracks, the Wardens' Keep ("Wider"), under the barrows (Ysmay comes down),
Breaking the Lockstone (Morvath carries the priests' own lanterns into the cracks), Kindling the Elderwold,
the Ford ("Fewer than they think"), Ash on the Snow, the Maw Wakes, the Red Sky Throne at Highmere. Ending:
Skarn is the Red Sky King; Ithra looks south at something pale being crowned.

### The Briar Oath (Thornwood)

Cerrid Ashbark goes to war for the last grove and learns what his own druids kept quiet. Beats: Axeford,
the fire-camp, the ambush at the stumps (Cerrid recognises his sister and lets her go), hunters in the snow
(the seer: "the summer was stolen"), the Fen's Edge (Brakka: "what the roots were for"), What the Roots
Remember ("We knew"), Kindling, the Last Grove (the Mother's seed), Seed of the Mother, the Briar Seal.
Ending: the wyrdthorn is planted at the lip of the Wound; Cerrid writes to Maelis, and begins with "Branwen".

### The Shuttered Halls (Forge)

Gunnra Sootmantle is the only one who believes the rock will not keep the fire out. Beats: Deep Shift (Forge
dead climb the shafts; below the shafts, a stair the Forge never cut), Bones in the Seams (her grandmother's
rune), the Debtors' Road (Wren at the gates), Iron for Bread (the axe message), Heat from Below, the Fallen
Hold (Tobbin's forbidden engine), the Wardens' Keep, Ore and Ember, the Molten Engine, the Second Lockstone.
Ending: a new Lockstone, too big to carry alone; Gunnra opens the gates.

### The Ashwinter (Frostmarch)

Ulvra Kettleborn unites the clans by the axe and leads them south for bread, and finds the old promise.
Beats: the Sun Goes Out, One Hall (Clan Whaleroad is the last to kneel, and keeps a cairn it never speaks
of; nobody remembers the last verse of the Sealing song), South for Bread, the Iron Pass, the Granary of
Highmere, Deer of the Old Wood, Cold Bones (the last verse on a cairn), the Source of Winter ("winter does
not come from the north; the clans carry it"), Wyrm-Wake, Bring the Winter. Ending: the fires bank low;
Ulvra sits in the snow and waits to find out whether anyone will pay this time.

### The Long Watch (Concord, three chapters)

A short side campaign set in the Year After, on the Highmere road: Wren and Maelis hold Last Watch against
the broken Host's last seven banners, then carry Reedhaven's oathstone into the Stone Heart under the
ridge, where a scar in the living rock takes it. It uses the survival, defence and labyrinth scenario
recipes.

### Editorial changes of 2026-11-09

- Every named enemy now stands on the map (new `cast` heroes on 22 generated chapters, see section 5).
- Maelis Thorne's Thornwood name is Branwen Ashbark. It appears in The Last Light chapter 6 and closes The
  Briar Oath.
- The Long Watch is rewritten into the world (it had placeholder lore).
- Seeds for the expansions: the uncut stair under Stonevow (Shuttered Halls 1), Clan Whaleroad and its cairn
  (Ashwinter 2), the fish-folk on the Living Shore (Pale Inheritance 3 outro).
- Objective and mechanic wishes per chapter went to the map overhaul.

## 3. The Six Eyes (Umbral Court expansion, the Year After)

**Premise.** The Court has stayed below for a thousand years. This year the deep is breached from above by
Forge miners gone mad, and the Nightgate Wardens learn that the surface peoples have been "turned": each is
being driven cruel by the Gate-Eye it holds. Matriarch Ulmarra, Veilseer of the Wardens, sends the young
Dreadmarshal Serane Nhalvor up the Long Stair to free the surface peoples one by one and bring the Eyes
home to be cleansed in the deep. Rhuvel Askai, a Nightstalker who has been to the surface before, goes with
her and doubts everything. The Court frees six peoples, collects six Eyes, and carries them down into the
dark, where Ulmarra sets them into the Nightgate. That was always the plan. Ulmarra is Vexmire. The dragon
wakes.

**The Eyes** (`data/artifacts.json`, charm slot, relic rarity, each with a gift and a flaw):

| Eye | Held by | Where | Found as |
|---|---|---|---|
| Eye of the Anvil | Forge | Kharrak Hold | the keystone of the Worldforge's arch |
| Eye of the Saint | Concord | Greyhold chapel | the jewel in Saint Orrin's reliquary |
| Eye of the Root | Thornwood | the Last Grove | the stone Brakka's seed grew around |
| Eye of the Regent | Hollow | Sallowmere | Ysmay's own pendant; she is not corrupted and trades it |
| Eye of Embers | Ashen | Cindermaw | Skarn's trophy from Highmere's treasury; the Host was never "turned" |
| Eye of Winter | Frostmarch | the Ancient Glacier | frozen into the winter wyrm's cairn |

**How the twist is seeded.** Ulmarra always says "bring it home". Rhuvel notices that the Eyes react to one
another, not to the deep. Ysmay says she has met Ulmarra before, three hundred years ago, under another
name. The freed Concord turns on the Court at the Heartroots (chapter 5's betrayal) because Aldous Wren,
free of the Eye, has understood what the Court is carrying; the player is told he relapsed. In chapter 9
every "freed" people hunts the Court down the Long Stair. Chapter 10 reads all of it the other way.

**Chapters** (campaign `six_eyes`, tiers 2, 3, 3, 4, 5, 5, 6, 7, 8, 8):

1. *Below the Sky* (hand-made, underground). House Draal seizes the Wardens' tithe-caverns. Serane retakes
   them. Ulmarra praises her and mentions the Stair.
2. *The Stair Goes Up* (L). Forge miners break into the deep, howling about an eye that watches them. Rhuvel
   joins. The Wardens follow the breach up.
3. *Under the Sky* (T, townless start). The Court stands under the sky for the first time in a thousand
   years, with no town. Villages of the Forge's outer steadings, then Kharrak Hold and the Eye of the Anvil.
   Gunnra Sootmantle, freed, does not thank them.
4. *The Saint's Eye* (C). Greyhold. Aldous Wren has had his own villages burned for impurity. Serane takes
   the chapel and the Eye; Wren wakes and asks what year it is.
5. *Thorn and Mirror* (B). The freed Concord marches with the Court to the Last Grove, then turns at the
   Heartroots. Brakka's Eye of the Root. Ulmarra: "The Eye's grip does not let go all at once."
6. *The Regent's Price* (A, 2v2 with the Hollow). Ysmay is not turned and will not be freed. She sells her
   Eye for help against the Red Sky King's leftover brood in the Barrow Below. Her outro names Ulmarra.
7. *Red Sky, Black Teeth* (C). Cindermaw. Skarn Ashborn has the Eye of Embers as a trophy and is the only
   honest enemy in the campaign.
8. *The Winter's Eye* (C). The Ancient Glacier. Ulvra Kettleborn feeds her own clans to the wyrm. Six Eyes.
   Rhuvel: "Five of them looked at us the same way."
9. *The Long Stair Down* (S, survival). Carry the Eyes home while every freed people pursues. Hold the
   Stair-Hold until Ulmarra's door opens.
10. *The Nightgate* (F, hero-only, no town). Ulmarra sets the Eyes in the gate and takes House Vexmire's
    side. Karzhaloth wakes. Serane and Rhuvel fight the gate-hold and then the dragon with what they carry.

**Karzhaloth** (`ancient_dragon`, `data/creatures/wilds.json`): a single boss creature. Eyeless, the sockets
sealed with the Court's old silver, which cracks as the Eyes return. Flying, breath that burns two stacks,
splash, fear, regeneration, no morale, stuns on its blows. It is worth about as much as a full tier 8 army
and is meant to be beaten by the finale's veterans with everything they have.

## 4. The Drowned Oath (Abyssal Shoal expansion, the Year After)

**Premise.** Four hundred years ago the learned city of Sarranth fled the Second Burning into the sea. The
breathing-spell that let its people live below went wrong: one rune of it was changed by Skadric Whalebone,
a shaman of the north who envied them, and the Sarranthi became the Shoal: strong, long-lived, forgetful,
slow. This year a young one, Ilo, who can read, finds the tablets of Sarranth in a drowned vault, learns
what his people were and who did it, and drags the Shoal onto the mainland to take revenge on the north.
He arrives as the Red Sky war is ending. The surface peoples do not know what the Shoal is. The Shoal
helps finish the Host, which earns it a welcome, and finds that nobody will stop it marching north.
But the Shoal cannot bear the cold. The Forge makes furnace-mail. The Forge does not give things freely.

**Chapters** (campaign `drowned_oath`, tiers 2, 3, 3, 4, 5, 5, 6, 7, 8, 8):

1. *The Tablets of Sarranth* (hand-made, swamp coast). Ilo reads; Chief Gorrok Bluntjaw forbids; Thunn
   Reefbreaker, Ilo's friend, stands with him. Take Gorrok's reef.
2. *One Shoal* (L). Mother Urrh's shoal is the last to follow. Sael Hookhand joins.
3. *Landfall* (C). The Living Shore. Ashen stragglers under Garsh Emberclaw hold the coast; the dead watch
   from the fens; Sister Edda Vey's lamp burns white near the Shoal, not blue.
4. *The Last Brood* (A, 2v2 with the Concord). Wren and the Shoal break two broods on the Barrow Roads. The
   Concord owes the Shoal now, and still does not know what it is.
5. *The Price of Iron* (C). The Forge refuses furnace-mail: "We gave the Concord a stone and were paid a
   hundred years late. We give nothing freely." Take Kharrak Hold's forges.
6. *Three Weeks of Fire* (S, survival). Hold Kharrak's furnaces for 21 days against Forge counter-sieges
   while the Forgewarm Harness is made. Reward: the three pieces.
7. *The Cold Road* (C). The Iron Pass and the southern clan halls. The first snow; without the Harness the
   Shoal would die on it. Nobody asks what the fish-folk want in the north.
8. *Who Pays the Clans* (B). The Concord marches with the Shoal against the clans' halls, then Wren pays the
   Concord's old debt and turns. Trigger: the Shoal takes its second clan hall.
9. *The Whaleroad Cairn* (T, townless start). Nothing of the Shoal's can live on the glacier. Villages are
   the rivermouth camps; the goal is Skadric's cairn. His own hand carved the confession: "I changed one
   rune. They would have left us in the cold."
10. *Who Was Cold First* (F, one against two). Kettlehall and the Hall of the Endless Feast, against the
    clans and the Concord. Ilo burns the hall, stands in its heat, feels his skin begin to remember, and
    walks back out into the cold with his people.

**Cold** (mechanic for a code thread; flagged in the requirements): the Shoal's hostile terrain is the
snowfield. On snow a Shoal army whose hero wears fewer than two pieces of the Forgewarm Harness loses a share
of every stack each day. The Harness (`data/artifacts.json` set `forgewarm`) makes snow count as neutral
ground at two pieces and speeds the army across it at three.

## 5. Where the text lives

- Chapter text, casts, setups and rewards: `data/campaigns.json`.
- Hand-made maps: `tools/maps/build_*_maps.py` (edit the builder, rerun it with `data/maps`).
- Campaign illustrations: `assets/specs/campaign_illustrations.json` scenes and
  `assets/source/batches/<batch>/prompt.txt`; the pipeline exports to `assets/illustrations/`.
