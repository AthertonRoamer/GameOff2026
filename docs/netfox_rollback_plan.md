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

## Phases
1. **Foundation**: `RollbackGameManager` (holds `game_loaded` until time sync is done, then starts on an agreed future tick), deterministic player roster helper with authority setup, `NetInput` base, configuration group, diagnostics overlay.
2. **Rollback demo**: new 2D demo and new configuration, `CharacterBody2D` player with `RollbackSynchronizer` and `TickInterpolator`.
3. **Actions**: `RewindableAction` shooting, projectile spawner with deterministic names, server-side lag-compensated hitscan, `StateSynchronizer` for server-owned state, optional `PeerVisibilityFilter`.
4. **Hardening**: mid-game leave/disconnect, return-to-lobby, packet-loss tests, bandwidth and rollback cost, two-machine Noray run, template README.
