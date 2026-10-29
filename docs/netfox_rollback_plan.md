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

## Phases
1. **Foundation** (done, see above): `RollbackGameManager` (holds `game_loaded` until time sync is done, then starts on an agreed future tick), deterministic player roster helper with authority setup, `NetInput` base, configuration group, diagnostics overlay.
2. **Rollback demo**: new 2D demo and new configuration, `CharacterBody2D` player with `RollbackSynchronizer` and `TickInterpolator`.
3. **Actions**: `RewindableAction` shooting, projectile spawner with deterministic names, server-side lag-compensated hitscan, `StateSynchronizer` for server-owned state, optional `PeerVisibilityFilter`.
4. **Hardening**: mid-game leave/disconnect, return-to-lobby, packet-loss tests, bandwidth and rollback cost, two-machine Noray run, template README.
