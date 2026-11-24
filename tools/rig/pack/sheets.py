"""What the packers need to know about a role's sheets: how each is played, how big it is drawn, and which forward sheet its head is lined up with."""

# the sheets that are not transitions: rendered state (= the name in the game) -> (frames per second, loops)
SHEETS = {
    "legs_idle": (8, True), "torso_idle": (8, True), "torso_idle_aim": (8, True), "torso_typing": (10, True), "torso_draw": (20, False), "torso_reload": (15, False), "legs_turn": (16, False),
    "legs_walk": (10, True), "legs_run": (15, True), "legs_side_walk": (10, True), "legs_side_run": (15, True), "legs_back": (10, True), "legs_back_run": (15, True),
    "torso_walk": (10, True), "torso_run": (15, True), "torso_side_walk": (10, True), "torso_side_run": (15, True), "torso_back": (10, True), "torso_back_run": (15, True),
    "death_front": (15, False), "death_front_right": (15, False), "death_right": (15, False), "death_back_right": (15, False), "death_back": (15, False),
}
TRANSITION_FPS = 15

# how big a gait is drawn in the game (its sheets, and the transitions to and from them), against how big it was rendered: the sideways steps a little smaller,
# the backwards ones a little bigger
GAIT_SCALE = {"idle": 1.0, "walk": 1.0, "run": 1.0, "side_walk": 0.97, "side_run": 0.97, "back": 1.05, "back_run": 1.05, "typing": 1.0}

# an upper body sheet's head is moved to where this forward sheet has it, so the head does not jump when the sheet changes
HEAD_REFERENCE = {"torso_side_walk": "torso_walk", "torso_side_run": "torso_run", "torso_back": "torso_walk", "torso_back_run": "torso_run"}
