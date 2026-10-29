# Rollback netcode for the multiplayer template

Client-side prediction and rollback on top of the existing lobby system, using the netfox addon (1.35.3, Godot 4.7, 2D).
Nothing in the lobby, mode, Noray or network code was changed. A game opts in by using `RollbackGameManager` instead of `BasicGameManager`.

## The model

- The **lobby instance** (peer 1) is the referee. It runs the same game scene as everyone else but is not a player.
- Each player's **body** belongs to the lobby. Each player's **Input node** belongs to that player's own peer.
- Players simulate their own body ahead of the server using their own input (prediction). When the lobby's state for a tick disagrees, netfox rolls back and resimulates.
- All time is counted in network ticks (`NetworkTime.tick`), 60 per second (project setting `netfox/time/tickrate`, synced to physics).

## Using it in a game

1. In the `Configuration` (the one on the `Main` node), set `game_manager_scene` to `rollback_game_manager.tscn` and `game_scene` to your game. `demo_games/demo_rollback_game/rollback_demo_configuration.tres` is a complete example.
2. The game's root node needs `start()` and `end()` methods, as with `BasicGameManager`. `start()` is called on every peer on the same tick.
3. In the game scene add a `RollbackPlayerSpawner` (set its `player_scene`), then in `_ready()`:
   ```gdscript
   spawner.player_spawned.connect(_on_player_spawned) # set position and other start state here
   spawner.setup(get_parent().lobby)
   spawner.spawn_all()
   ```
4. The player scene needs: a body with a `_rollback_tick(delta, tick, is_fresh)` method, a child named `Input` that extends `NetInput`, and a `RollbackSynchronizer` (state properties, plus the input properties from the `Input` node). Add a `TickInterpolator` for smooth display. See `demo_games/demo_rollback_game/player/`.
5. Release the game with `NetworkUnloader`, and call `spawner.quiesce()` in its cease step (see `rollback_demo.gd`). Without it, every game end logs "Node not found" RPC errors.

Scene files: node-typed exports such as `root` on the netfox nodes must be listed in `node_paths=PackedStringArray("root")` on the node line, or they load as null.

## Parts

| File | Purpose |
|---|---|
| `rollback_game_manager.gd/.tscn` | Drop-in `GameManager`. Reports the game loaded only after netfox's clock sync, then makes the lobby wait until every member's clock is healthy and starts everyone on one agreed future tick. |
| `rollback_player_spawner.gd` | One player per lobby member with the right authority. `quiesce()` stops sending before unload. |
| `net_input.gd` | Base class for the input node. Override `_gather()`. |
| `lag_compensator.gd` | Server-side history of positions per tick and `raycast()` against them, for instant weapons. |
| `rollback_diagnostics.gd` | F3 overlay: tick, round trip, clock offset, rollback cost. Switch on with `Configuration.rollback_diagnostics`. |

Configuration (`Rollback` group): `rollback_start_delay_ticks` (30), `rollback_sync_timeout` (30 s), `rollback_diagnostics` (off).

## Rules that are easy to get wrong

- **Health, score and other server-owned values are not rollback state.** Put them on a `StateSynchronizer`. Only the lobby changes them.
- **One-shot server effects must be deduplicated.** A late input makes the server resimulate, and a shot can then be confirmed on a different tick than before. Apply damage on `RewindableAction`'s `CONFIRMING` status and ignore a second damaging shot within about half a cooldown of an earlier one (see `_resolve_shot` in the demo player).
- **Cooldowns and other per-tick player state must be rollback state** (listed in the `RollbackSynchronizer`'s state properties), and must be set on every tick the action is active, not only when it is first confirmed.
- **Hitscan rewinds at least one tick.** A tick's positions are recorded only after every node has simulated it.
- **Respawning is not implemented.** Position is rollback state, so it cannot simply be set from outside a rollback tick.
- **Bad connections.** Tested at 80 ms each way: up to 2% loss each way is fine. At 5% each way, about 1 match in 10 had a client whose connection collapsed (ENet gave up). Netfox's clock sync is the weak spot under loss, which is why the lobby waits for healthy clocks before starting. Details and numbers are in `docs/netfox_rollback_plan.md`.
- **Noray over the internet has not been tested.** Only LAN and same-machine runs were done.

## Testing

All of these use the Godot console exe and run from the repository root. `tests/harness/run_smoke.ps1` has a `-Godot` parameter if your exe is elsewhere.

```
powershell -File tests/run_all.ps1                            # everything below, one PASS/FAIL line each (about 10 minutes)
powershell -File tests/harness/run_smoke.ps1                  # original demo: host, lobby, join, game, end
powershell -File tests/harness/run_smoke.ps1 -Rollback        # all peers start on the same tick (add -Clients 2 for 3 players)
powershell -File tests/harness/run_smoke.ps1 -Demo            # movement and shooting, every peer must agree
powershell -File tests/harness/run_smoke.ps1 -Demo -Rounds 2  # a second game in the same lobby
powershell -File tests/harness/run_smoke.ps1 -Leave           # a player leaves mid-game (-Kill: its process is killed)
powershell -File tests/harness/run_smoke.ps1 -Demo -LatencyMs 80 -LossPercent 2
powershell -File tests/harness/run_repeat.ps1 -Runs 10 -LossPercent 5   # repeat a lossy run and count failures
powershell -File tests/harness/run_lagcomp_check.ps1 -LatencyMs 120   # lag compensation on vs off
powershell -File tests/net/run_channel_probe.ps1              # delivery delay of RPC modes under loss
godot --headless --path . res://tests/unit/test_lag_compensator.tscn
```

`-LatencyMs`, `-JitterMs` and `-LossPercent` route the client through `tests/harness/latency_proxy.py` (needs Python). Set `HARNESS_CLOCK=1` to log each peer's netfox clock once a second.
