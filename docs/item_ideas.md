# Item ideas

Items players can find lying in rooms (the item rooms: each one has a chance, 30% by default, of holding a random item when the match loads). Anyone can pick a
found item up (E) and drop it (G), and a player who dies drops everything they carry. Found items are only visible in your cone of vision, or on the door console
when that room's camera is on. They never show on any map.

Each room can have its own list of items (an armory finds weapons, an office finds gadgets); a room with no list of its own uses the map's list.

**Status:** the first six (knife, smoke bomb, tripwire, coms hacker, night vision, radar) and the per-room item lists are built (see "How the first six work" below). The rest are ideas for review.

Questions for the reviewer are at the end.

---

## First batch (built)

### Knife
- Close range melee weapon. High damage, no ammo.
- Silent: no gunshot sound, no muzzle flash, so nobody hears or sees it from afar.
- Bonus damage on a target who is not facing you (a backstab).
- Natural pick for intruders and secretly attacking guards: it lets them kill without giving themselves away.

### Smoke bomb
- Thrown or dropped. Makes a cloud for a while that blocks sight: players can't see through it, cameras show nothing through it, and turrets can't aim through it.
- Mostly an escape tool for attackers, but guards can use it to cut off a corridor too.

### Tripwire
- Placed across a doorway or corridor. When someone crosses it, the player who placed it gets a ping on their map: *someone* crossed, and when. Not *who*.
- Can be seen up close and picked back up.
- Good for guards watching a relic room, and for attackers watching their back.

### Coms hacker
- Placed like the portable generator. While it runs, the player who placed it hears every chat message sent within a radius of it, including channels they
  normally can't hear (like the attackers' private channel).
- Has a small blinking light, so others can find it and shoot it. Finding one raises the question of who put it there.
- The main tool for catching a secret attacker among the guards.

### Night vision helmet
- Worn. While it is on, dark areas count as lit for you: you see players in the dark.
- Weakness: bright light blinds you. Walking into a lit room or looking into a flashlight beam whites out your view for a moment.
- So guards can fight it by switching lights on (which costs power).

### Radar
- Every 8 to 10 seconds it sends a pulse that briefly shows nearby players as blips, all round you (360 degrees), not only in your view cone.
- Only players who are moving show up, so sneaking slowly beats it.
- Not a constant view: that would be too strong.

---

## Other ideas

### Weapons and turrets
- **Mini portable turret:** placed, shoots on its own. The hard question is who it shoots, with secret teams. One option: it shoots anyone not on the placer's
  real team, so a guard's turret firing at another "guard" exposes a secret attacker. Great drama, but it may give too much away.

### Power and lights
- **Battery pack:** put it down to power a region for a while (a short-lived portable generator).
- **EMP grenade:** knocks out lights, cameras and turrets in a radius for about 10 seconds. A strong attacker tool against the security system.
- **Flare / glow stick:** a thrown light. Lets guards light a dark room without spending power.

### Doors and cameras
- **Door jammer:** holds one door open or shut without a console and without power. Counters door control.
- **Crowbar / lockpick:** opens a locked door, slowly and noisily.
- **Camera bug:** a portable camera you stick anywhere (outdoors, a corridor with no camera). Shows on the door console's map.

### Deception
- **Fake relic:** looks like an artifact. Attackers waste time on it; guards can't tell what was really taken.
- **Noise maker:** makes a decoy sound somewhere, to draw people there.
- **Cleaning kit:** hides a body and the blood, so a kill isn't found.

### Survival
- **Armor vest:** absorbs a set amount of damage.
- **Stim:** refills stamina or gives a short sprint boost.
- **Relic detector:** points toward the nearest artifact. Mostly useful to attackers.

---

## Balance notes
- Anyone can grab a found item, so think about which side each one helps:
  - **Attackers:** knife, smoke bomb, EMP, fake relic, cleaning kit, relic detector.
  - **Defenders:** flare, battery pack, camera bug, tripwire, coms hacker.
  - **Either:** night vision, radar, armor, stim, door jammer, noise maker.
- Per-room lists let us steer this: put attacker items deep in the facility and defender items near the security rooms, or the other way round.
- Strong items (radar, coms hacker, night vision) could be rarer: listing an item twice in a room's list makes it twice as likely there.

## Questions for the reviewer
1. Is the knife's backstab bonus a good idea, or should it just be high damage up close?
2. Should the tripwire tell you *who* crossed it, or only that someone did?
3. Should the coms hacker let you hear only the attackers' channel, or every channel you can't already hear?
4. Is night vision too strong if guards don't keep lights on? Should it run on a battery that runs out?
5. Radar: pulse every 8 to 10 seconds, moving players only. Too strong, too weak?
6. Which of the "other ideas" should come next?
7. Anything missing?

---

## How the first six work (as built)
| Item | Use | Details |
|---|---|---|
| Knife | chosen, click to strike | 26 damage from the front (two blows kill), 52 from behind (one kills). Reach about 1.5 m. Silent: no sound, no tracer, no muzzle flash, opens no door. `game/items/knife.gd` |
| Smoke bomb | chosen, click to throw (up to 300 px, stopped by walls) | a cloud about 5 m across for ~18 s (grows 1.2 s, thick 14 s, thins 3 s). Hides players, items, shots and blood behind it; turrets can't see through it; camera feeds show the cloud. Bullets go through. `game/gadgets/smoke_cloud.gd` |
| Tripwire | chosen, click (or G) to put down | a wire across the way you face, wall to wall, up to 4 m. Anyone else crossing it: you get a ping on your maps and a chat line naming the room, not who. Quiet for 3 s after. E takes it back. A found one is not armed until someone puts it down |
| Coms hacker | chosen, click (or G) to put down | hears chat sent within 12 m of it on channels you're not on, and shows you who sent it. Blinks red. One shot breaks it; anyone can take it with E. A found one listens for nobody until put down |
| Night vision | carried in any slot, N switches it | everyone in your view cone is seen in the dark. A lit room or another player's beam on you blinds it (white screen) until 1.2 s after the light is gone. Only you see it is on |
| Radar | carried in any slot | every 9 s a pulse shows players within 700 px who are walking or running (not still, not sneaking), through walls, for 2.5 s |

All of them are on both maps' item lists. Every number above is a setting on the item's `.tres` (or on the `Gadgets` node in `game.tscn`).
