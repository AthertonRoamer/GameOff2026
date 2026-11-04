# Netfox rollback for the multiplayer template

Goal: add client-side prediction and rollback (netfox 1.35.3, Godot 4.7.1, 2D) to `multiplayer_template/` without changing existing behavior. Work happens on `feature/netfox-rollback`, one commit per phase.

## Rules
- Existing files change only when unavoidable (`configuration.gd` new exports with off-by-default values, `project.godot` netfox time settings, and the configuration used by `main.tscn`).
- New code lives in `multiplayer_template/rollback/`. The base `GameManager`, `Lobby`, `LateLoadLobby`, modes, `NorayManager` and `Network` are subclassed or hooked, never edited.
- The existing demo (`DemoOne`) must keep working. Run the smoke harness after every phase.
- Tickrate target: 60 ticks/s with `netfox/time/sync_to_physics` on. Keep all game code tick-agnostic (`NetworkTime.ticktime`), and re-evaluate with `NetworkPerformance` measurements in Phase 4.

## Smoke harness
`tests/harness/` drives the real host and join code in two processes, with no menu clicks.

```
powershell -File tests/harness/run_smoke.ps1            # LAN: host, lobby instance, join, game start/end
powershell -File tests/harness/run_smoke.ps1 -Noray     # same, joining through Noray
```
Defaults to the Godot console exe at `C:\Users\yello\Downloads\Godot_v4.7.1-stable_win64.exe\`. Pass `-Godot <path>` to override. Note `Main` must be added at `/root/Main` or the RPC node paths will not match the lobby instance.

## Phase 0 findings (baseline, no template changes)
- The configuration that actually runs is the **inline sub-resource in `main.tscn`**, not `default_configuration.tres`. It uses `LateLoadLobby`, `DemoOne`, and starts the lobby instance with `--headless --debug-menu`. The lobby instance therefore has no rendering.
- LAN baseline passes: host -> lobby instance -> client join -> `LateLoadLobby` load barrier -> game start -> end. The `@rpc` annotation concern on `LateLoadLobby.begin_game()`/`end_game()` is not a problem in 4.7.1.
- netfox is already live: the autoloads are registered, and the tickrate handshake plus time sync already run between every client and the lobby (peer 1) at the default 30 ticks/s. Clients take the tickrate from the server, so the project setting must match across builds.
- Noray baseline: registration and game ID publishing work (lobby side). A client on the **same PC** fails (NAT attempt hits this machine's own public IP, relay attempt times out with handshake error 24). Not conclusive: needs a two-machine run to know whether it is the network or the template.
- Pre-existing, harmless: `player.tscn` references an invalid UID for `icon.svg` and falls back to the path.
- netfox API notes: `RollbackSynchronizer` needs `process_settings()` after authority is set. `RewindableAction` is marked experimental. There is no built-in hitscan lag-compensation service. `NetworkRollback.mutate()` re-simulates affected nodes from a tick.

## Phase 1 status: done
Added in `multiplayer_template/rollback/`:
- `RollbackGameManager` (+ `.tscn`): same contract as `BasicGameManager` (`game_scene` from the configuration, game root has `start()` / `end()`). Holds `game_loaded` until `NetworkTime` has synced. On start, the lobby waits until every member's clock is synced (`rollback_sync_timeout`), picks `NetworkTime.tick + rollback_start_delay_ticks` and sends it to everyone, so all peers call `start()` on the same tick.
- `RollbackPlayerSpawner`: one player per lobby member under the spawner node, named by peer id. Body authority is the lobby (peer 1), the child `Input` node's authority is the member's peer. `player_spawned` fires before the player enters the tree (set start position there). Removes players on `member_left`.
- `NetInput`: base class for the input node, `_gather()` runs once per frame before the tick loop, only on the owning peer. (`BaseNetInput` comes from `netfox.extras`, which is not installed.)
- `RollbackDiagnostics`: F3 overlay with tick, rtt, clock offset, rollback cost. Enabled by `Configuration.rollback_diagnostics`.
- `Configuration`: new "Rollback" export group (`rollback_start_delay_ticks` = 30, `rollback_sync_timeout` = 5.0, `rollback_diagnostics` = false). Defaults leave existing behavior unchanged.
- `project.godot`: `netfox/time/tickrate = 60`, `netfox/time/sync_to_physics = true`.

How to opt in: set `game_manager_scene` on the configuration to `rollback_game_manager.tscn`, and `game_scene` to your game.

Verification: `run_smoke.ps1` (original demo) passes unchanged; `run_smoke.ps1 -Rollback` passes with host and client both starting on the scheduled tick (`tests/harness/probe/` is a throwaway game used only for this check).

## Phase 2 status: done
Added `multiplayer_template/demo_games/demo_rollback_game/`:
- `rollback_demo.tscn` / `.gd`: 2D arena, spawns players with `RollbackPlayerSpawner`, same quit/unload flow as `DemoOne`.
- `player/rollback_demo_player.tscn`: `CharacterBody2D` that simulates in `_rollback_tick`, with `RollbackSynchronizer` (state: `:position`, `:velocity`; input: `Input:movement`) and `TickInterpolator` (`:position`). The local player is tinted green.
- `rollback_demo_configuration.tres`: the same setup as the inline configuration in `main.tscn`, but with `RollbackGameManager`, the rollback demo and the diagnostics overlay on. `main.tscn` is untouched.
- `RollbackPlayerSpawner.quiesce()`: stops the players' synchronizers sending before the game is unloaded. Without it, every game end logs "Node not found" RPC errors from packets that were in flight while the other side had already freed its nodes.

To try it by hand: open `main.tscn`, select the `Main` node, set its Configuration to `rollback_demo_configuration.tres`, run two instances, host in one and join in the other. Arrow keys move, F3 toggles the overlay.

Verification (`run_smoke.ps1 -Demo`): the client holds "move right" for a second; its player moved about 250-260 px, responded within 2 frames, and the host's and client's final positions of every player match exactly. `run_smoke.ps1` (original demo) and `-Rollback` (probe) still pass.

Not covered yet: loopback has no latency, so this run does not prove that prediction hides real latency or that reconciliation corrects mismatches. That needs the latency and packet-loss testing in Phase 4. Only two players were tested, and the lobby process's own log is not captured.

## Phase 3 status: hitscan shooting done, projectiles and visibility filtering not done
Added:
- `multiplayer_template/rollback/lag_compensator.gd` (`LagCompensator`): server-side position history per rollback tick plus `raycast()` against circles as the shooter saw them. The shooter reports its view lag (ticks) as an input property, the lobby clamps it (`max_rewind_ticks`, default 12 = 200 ms) and rewinds targets by it. 2D only. Netfox does not provide this.
- Demo weapon (`rollback_demo_player.gd`, `rollback_demo_input.gd`): `RewindableAction` for the shot; input properties `fire`, `aim`, `view_lag`; `last_fire_tick` is rollback state (cooldown); health is not rollback state, the lobby owns it and a `StateSynchronizer` sends it. Hit resolution runs only on the lobby, on the action's `CONFIRMING` status. The shooter predicts the tracer immediately.
- `RollbackPlayerSpawner.quiesce()` now also quiets `StateSynchronizer`s.
- Tests: `tests/unit/test_lag_compensator.tscn` (22 checks, offline, run as a scene because `--script` mode has no autoloads), `tests/harness/latency_proxy.py` (local UDP proxy with delay, jitter and loss for the client's connection), `run_smoke.ps1 -Moving -LatencyMs N [-NoLagComp] [-LossPercent N]`, and `run_lagcomp_check.ps1`.

Pattern worth keeping: a one-shot server effect (damage) must be deduplicated per shot. A late input makes the server resimulate, and the same shot can then be confirmed on a different tick than before. The demo ignores a second damaging shot within `fire_cooldown_ticks / 2` of an earlier one.

Measured (loopback plus the latency proxy, two players, one machine):
- Prediction hides latency: the local player moves within 2 frames at 260 ms round trip.
- Lag compensation, shooter and target running side by side, 16 px hit radius, about 8 shots: 120 ms each way (about 260 ms RTT): 7-8 hits with it, 1 without. 200 ms each way (440 ms RTT, past the 200 ms rewind cap): 8 with, 1 without. 40 ms each way: all shots hit either way, so it only matters at higher latency. Shot counts are the client's own estimate and can be off by one.
- Loss at 80 ms each way: 0%, 1% and 2% each way pass every check. At 5% each way it breaks: netfox rejects thousands of inputs as "older than 64 frames" and the host never sees the client's player move. Suspected cause (not confirmed): ENet holds unreliable packets behind a lost reliable one on the same channel. This is the first item of Phase 4.

Not done: projectiles (deterministic names, spawn and despawn under resimulation), respawn (position is rollback state, so it needs to go through the rollback system), `PeerVisibilityFilter`, line-of-sight blocking for shots, and hit shapes other than circles.

## Phase 4 status: hardening done except real-network Noray testing; one loss problem remains
Run everything with `powershell -File tests/run_all.ps1` (about 10 minutes, needs Python for the latency checks). Last run: all 11 checks pass.

Scenarios now covered by `tests/harness/run_smoke.ps1`: 3 players (`-Clients 2`), a second game in the same lobby (`-Rounds 2`), a player leaving gracefully (`-Leave`), a player's process killed (`-Kill`; the host notices after ENet's timeout, 8 s here, and keeps running).

Fixes made in this phase:
- `RollbackPlayerSpawner.quiesce()` did nothing useful and logged an error for a peer that had already left. It now returns early when this peer is disconnected.
- `RollbackGameManager` now waits for every member's clock to be healthy (`NetworkTime.clock_offset` within 50 ms, reported by each member every half second) before scheduling the start, not just for netfox's initial sync to be done. `rollback_sync_timeout` default raised from 5 s to 30 s, and the lobby starts anyway with a warning if it runs out.

The packet-loss investigation (80 ms each way):
- ENet is not stalling state behind reliable traffic. A probe (`tests/net/run_channel_probe.ps1`) at 5% loss: `unreliable`, `unreliable_ordered`, and `unreliable_ordered` on its own channel all arrive with median 88 ms, 95th percentile 91 ms, worst 148 ms. Only `reliable` is slow (95th percentile about 1.2 s, worst about 1.6 s, from retransmissions).
- The cause of the failures was netfox's clock sync. A client asks the lobby for its clock with a reliable message; under loss the answer can be seconds late, the client ends up seconds behind, netfox logs "Offset ... is above panic threshold", and the client then needs about 20 s at its maximum 1.25x speed to catch up. Inputs stamped with the wrong tick are rejected as "older than 64 frames".
- Before the clock-health wait: about 3 of 9 runs at 5% loss each way failed. After: 2 of 22 failed (1 of 10, 1 of 12).
- The 2 remaining failures are different: the client's measured round trip climbs from 1 s to 8.7 s and the connection ends with "Peer 1 disconnected" (ENet gave up). Frame-hitch logging showed no freezes in any process, and the latency proxy logged no errors, so it is not this test machine or the proxy as far as I can tell. I could not fix it from the template.
- At 2% loss each way: 8 of 8 passed (one of them logged 446 rejected inputs and still passed). At 0%: 6 of 6.
- Practical reading: the template is sound up to about 2% loss at 80 ms each way. At 5% each way (a very bad connection) expect roughly 1 match in 10 to have a client whose connection collapses. This was measured with the lobby and players on one PC and a Python proxy, not on real networks.

Cost (rollback demo, 60 ticks/s, one connection per player, measured over 7 s of play with some movement and shooting):
- 2 players: host 23.8 kB/s sent and 21.5 received; client 15.9 sent and 14.5 received. Rollback loop about 1-2 ms per frame.
- 3 players: host 35.9 / 38.2 kB/s; the other two 23.9 / 25.7 and 35.8 / 38.2. The lobby's total is the sum of every player's connection, roughly 100 kB/s (0.8 Mbit/s) for 3 players. The lobby usually runs on the host's own machine, so this is the host's upload.
- These are numbers for this small demo (position, velocity, one cooldown value and four input values per player). A game with more state will cost more. Not measured: more than 3 players, or a bigger game.

Not tested by me and needs two machines: Noray over the real internet. The same-PC attempt in Phase 0 failed (it tries to connect to the PC's own public address, then the relay timed out), so whether it works on your network is unknown. To try it: on machine A set the `Main` configuration to `rollback_demo_configuration.tres`, run the game, host with Noray and copy the Game ID; on machine B run the same build with the same configuration, choose Join, paste the Game ID, and check that both players see each other move and that shooting works. If the join fails, note whether the log says the NAT punch or the relay failed.

Still not done: `PeerVisibilityFilter`, line-of-sight for the instant shot, non-circle hit shapes (projectiles now stop at walls).

## Phase 5 status: projectiles and respawn done
- **Respawn** (demo player): `dead_since` and `last_alt_tick` are rollback state. The lobby sets `dead_since` when health reaches 0 and, after `respawn_ticks` (120 = 2 s), restores health and moves the player to `spawn_position`. Clients get the position and `dead_since` through the normal state sync and roll back. The dead cannot be hurt and are skipped by hitscan and projectiles.
- **Projectiles** (`rollback/projectile_manager.gd`): position is a pure function of origin, direction and fire tick, so nothing is synced per tick. The shooter predicts its own projectile; the lobby sends the shot to the other clients, finds hits tick by tick (including ticks it was confirmed late for) and tells clients to remove it. Repeated spawns from a resimulation are deduplicated.
- **Added** `LagCompensator.sweep()` (moving circle against tracked nodes) and a `filter` argument on `raycast()`.
- **Tests:** `-Combat` scenario (client fires three projectiles, 40 damage each; every peer must see the victim at 0 hp, then back at the respawn point with full health). Passes for 2 and 3 players and at 80 ms each way with 2% loss (6 of 6). The combat check reports what each peer sees rather than reading a clock, because on a lossy link peers start the game a moment apart.
- **Loss regression found and mitigated:** at 80 ms and 2% loss the plain demo failed about 6 of 27 runs after the new state was added (the committed Phase 4 code: 0 of 10). Cause: a client whose clock is still catching up makes netfox print thousands of "older than 64 frames" lines a second; writing them froze the host for about 6 s, which broke its own clock. With netfox logging off the demo failed 0 of 12. `RollbackGameManager` now mutes netfox logging from game load until the game starts (`rollback_quiet_loading`, on by default); with that, 1 of 15 runs failed and the cause of that one was not examined. Treat 2% loss as mostly fine, not guaranteed.
- **Known limits:** projectile hits use targets' positions on the tick the projectile reaches them (no extra rewind for the shooter's view lag). Wall collision uses a physics layer mask on the lobby only, so a client may draw a projectile a moment past a wall until the lobby's removal arrives. Invulnerability after respawn is not implemented.

## Phases
1. **Foundation** (done, see above): `RollbackGameManager` (holds `game_loaded` until time sync is done, then starts on an agreed future tick), deterministic player roster helper with authority setup, `NetInput` base, configuration group, diagnostics overlay.
2. **Rollback demo**: new 2D demo and new configuration, `CharacterBody2D` player with `RollbackSynchronizer` and `TickInterpolator`.
3. **Actions**: `RewindableAction` shooting, projectile spawner with deterministic names, server-side lag-compensated hitscan, `StateSynchronizer` for server-owned state, optional `PeerVisibilityFilter`.
4. **Hardening**: mid-game leave/disconnect, return-to-lobby, packet-loss tests, bandwidth and rollback cost, two-machine Noray run, template README.
