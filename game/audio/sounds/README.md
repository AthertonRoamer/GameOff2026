# Sounds

Drop audio files (.wav or .ogg) into a folder here and they are used the next time the game runs, with no other setup. Several files in one folder are
variations of the same sound; one is picked at random each time and never the same twice in a row.

| Folder | Used by | Definition |
|---|---|---|
| footsteps/ | every footstep, walk and run | ../definitions/footstep_walk.tres and footstep_run.tres |
| weapons/pistol/ | the pistol's shot | ../definitions/pistol_shot.tres |
| weapons/rifle/ | the rifle's shot | ../definitions/rifle_shot.tres |
| doors/open, doors/close, doors/locked | a door opening, closing, or locked | ../definitions/door_*.tres |

Short sounds, recorded dry (no echo: the game adds the echo itself) and mono, work best. Click a definition in the editor to change its volume, pitch
variation, how far it carries (range_m) and how it fades. A new kind of sound is a new SoundDef resource (copy one) pointed at a new folder.
The map's effect on sound (walls, doors, muffling, echo) is in ../acoustics.tres; the filters and reverb are on the audio buses (bottom panel, Audio).

Footsteps were cut from a single recording by tools/audio/cut_steps.py (python cut_steps.py recording.wav game/audio/sounds/footsteps stone).
