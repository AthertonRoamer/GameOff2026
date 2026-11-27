# Text chat

Two channels:
- **Guards**: every player with a guard role, loyal or secretly attacking.
- **Intruders**: every attacker, meaning intruders and the secretly attacking guards (imposters).

Imposters are on both. There is no chat in a deathmatch or the playground.

## Files
| File | What it does |
|---|---|
| `game/chat/chat_rules.gd` | Who is on which channel, the name a reader sees, cleaning the text, and the rate limiter. Pure logic, tested by `tests/unit/test_chat.tscn` |
| `game/chat/chat_relay.gd` | The `ChatRelay` node in `game.tscn`. A client sends its message to the lobby. The lobby checks it and sends it on **only** to the players on that channel, so nobody receives a message they may not read |
| `game/chat/chat_window.tscn` / `.gd` | The window in the HUD (`ChatWindow` in `player_hud.tscn`) |

## Moving and resizing the window
Open `game/player_hud/player_hud.tscn`, select `ChatWindow`, and drag it or its handles. You can also set anchors and offsets in the inspector. Everything inside it is a container, so any size works: tall above the minimap (the default, above the power readout) or a long, low strip next to the inventory. Below about 140 × 72 it stops shrinking.

On the `ChatWindow` node you can set:
- the tab colours (green GUARDS, red INTRUDERS)
- the tab font sizes (active and inactive)
- name colours, log font size and how many lines are kept
- the ding: any `AudioStream`; empty means a chime made in code, plus volume and bus

## Controls
- **Enter** starts typing. Enter again sends; Esc or clicking outside the window stops typing.
- Clicking on the window also starts typing.
- While typing, the player doesn't move, shoot or use E.
- Imposters switch channels with **C** or by clicking a tab. The other tab shows a bubble counting messages not read there yet.

## Rules and safeguards (on the lobby)
- **Channel checks.** A player may only send on their own channels, and their name comes from the lobby, never from the client.
- **Dead players** can read but not send (`ChatRelay.dead_can_send` turns that off).
- **Text cleaning.** Line breaks and control characters (including text-reversal marks) are removed, spaces are collapsed, and messages are capped at 200 characters. Formatting tags are shown as typed.
- **Rate limit.** A burst of 4 messages, then one every 1.5 s. Sending the same text again within 10 s is refused. 3 refusals within 10 s mute the player for 20 s. The tuning is in `ChatRules.RateLimiter`.
- **Unknown senders.** When two imposters aren't told about each other (`Game.attacking_guards_know_each_other` off), each shows to the other as "Unknown ally" on the intruder channel. `ChatRelay.reveal_unknown_attackers` shows real names instead.

## The ding
It's a plain `AudioStreamPlayer`: not positional, and not part of the game's sound system. It only plays on peers the lobby sent the message to, so nobody else can hear it.
