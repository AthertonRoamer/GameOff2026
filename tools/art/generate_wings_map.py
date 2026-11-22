"""Seeds game/environment/facility_map_wings.tscn: the big facility campus, as a map scene to edit in the editor.
ONE TIME, like convert_layout_to_scene.gd: running it again overwrites the scene and any editing done to it since.
    python tools/art/generate_wings_map.py            (run from the project folder; needs Pillow for the picture)
It checks the layout (no two rooms touch, every door joins the two rooms it says, everything can be walked to from the atrium), prints the walking distances
between the spawn, entrance and extract rooms, and draws docs/night_shift/map_wings_plan.png.

The grid: a module is 1 m (4 map cells of 0.25 m). A room is whole modules less the one cell wall it keeps from the next room, so rooms that sit side by side in
module space are one wall apart. Doors go in those walls.
The campus: a 30 x 22 m atrium with four wings of different lengths and shapes (north and south end in a horizontal concourse, east and west in a vertical one), a
main corridor 6 m wide down each wing with a stack of rooms either side, outdoor courtyards and pads, and a hangar in the north east. It is not symmetrical on purpose:
the intruder's ways in are in the west, north and south, and the ways out in the east.
"""
import heapq, math, os, sys
from collections import deque

OUT_SCENE = "game/environment/facility_map_wings.tscn"
OUT_PLAN = "docs/night_shift/map_wings_plan.png"
TILE = 11  # px per cell
CORRIDOR, UTILITY, ITEM, OFFICE, EXTERIOR, OUTDOOR = range(6)
NONE, CAMERAS, DOORS, LIGHTS, GENERATOR, TURRETS, POWER = range(7)
KIND_COLOURS = ["#8aa0b8", "#6fd3e8", "#c9a0ff", "#9ad1a0", "#f2b544", "#7a7f88"]

ROOMS = {}  # id -> dict(name, kind, function, rects: [module rects (x, y, w, h)])


def room(rid, name, kind, function, *rects):
    assert rid not in ROOMS, rid
    ROOMS[rid] = dict(name=name, kind=kind, function=function, rects=list(rects))


def stack_y(x, y0, w, items):
    """rooms one under the other, each (id, name, kind, function, height), in a column x wide starting at y0; returns the ids"""
    ids, y = [], y0
    for rid, name, kind, function, h in items:
        room(rid, name, kind, function, (x, y, w, h)); ids.append(rid); y += h
    return ids


def stack_x(x0, y, h, items):
    """rooms side by side, each (id, name, kind, function, width), in a row h tall starting at x0"""
    ids, x = [], x0
    for rid, name, kind, function, w in items:
        room(rid, name, kind, function, (x, y, w, h)); ids.append(rid); x += w
    return ids


# ------------------------------------------------------------------ the campus
room("atrium", "Central Atrium", CORRIDOR, NONE, (64, 62, 30, 22))

# north: Security. A tall corridor off the atrium ending in a concourse along the front, with the way in at its middle
room("north_corridor", "North Corridor", CORRIDOR, NONE, (76, 28, 6, 34), (52, 22, 54, 6))
stack_y(62, 28, 14, [("north_armory", "Armory", ITEM, NONE, 10), ("north_evidence", "Evidence Room", ITEM, NONE, 8), ("north_interview", "Interview Rooms", OFFICE, NONE, 8),
                     ("doors_north", "North Door Control", UTILITY, DOORS, 8)])
stack_y(82, 28, 10, [("north_cameras", "Camera Room", UTILITY, CAMERAS, 12), ("north_turrets", "Turret Control", UTILITY, TURRETS, 8), ("north_lockers", "Locker Room", OFFICE, NONE, 6),
                     ("spawn_north", "Guard Post", OFFICE, NONE, 8)])
stack_x(52, 12, 10, [("entrance_garage", "Parking Garage", EXTERIOR, NONE, 12), ("entrance_north", "North Gatehouse", EXTERIOR, NONE, 14), ("north_registry", "Registry", OFFICE, NONE, 10),
                     ("north_briefing", "Briefing Room", OFFICE, NONE, 10), ("north_annex", "Records Annex", OFFICE, NONE, 8)])
room("pad_north", "North Pad", OUTDOOR, NONE, (56, 4, 46, 8))

# east: Power. A long corridor out of the atrium past a huge generator hall, ending in a vertical concourse with the way out
room("east_corridor", "East Corridor", CORRIDOR, NONE, (94, 69, 46, 6), (140, 46, 6, 47))
stack_x(94, 52, 17, [("doors_east", "East Door Control", UTILITY, DOORS, 12), ("east_generator", "Generator Hall", UTILITY, GENERATOR, 24), ("east_breakers", "Breaker Room", UTILITY, POWER, 10)])
stack_x(94, 75, 12, [("spawn_east", "Crew Room", OFFICE, NONE, 10), ("east_workshop", "Maintenance Bay", OFFICE, NONE, 12), ("east_stores", "Parts Store", OFFICE, NONE, 12),
                     ("east_pump_house", "Pump House", UTILITY, NONE, 12)])
stack_y(146, 46, 12, [("east_plant_office", "Plant Office", OFFICE, NONE, 10), ("extract_east", "East Loading Dock", EXTERIOR, NONE, 14), ("east_cold_store", "Cold Store", UTILITY, NONE, 12),
                      ("extract_rail", "Rail Platform", EXTERIOR, NONE, 11)])
room("pad_east", "East Pad", OUTDOOR, NONE, (158, 56, 8, 37))

# south: Staff. A corridor down to a concourse along the back, a big cafeteria, a vehicle yard
room("south_corridor", "South Corridor", CORRIDOR, NONE, (70, 84, 6, 36), (44, 120, 58, 6))
stack_y(56, 84, 14, [("spawn_south", "Barracks", OFFICE, NONE, 14), ("doors_south", "South Door Control", UTILITY, DOORS, 8), ("south_dormitory", "Dormitory", OFFICE, NONE, 14)])
stack_y(76, 84, 14, [("south_break_room", "Break Room", OFFICE, NONE, 10), ("south_cafeteria", "Cafeteria", OFFICE, NONE, 18), ("south_infirmary", "Infirmary", UTILITY, NONE, 8)])
stack_x(44, 126, 10, [("entrance_service", "Service Exit", EXTERIOR, NONE, 12), ("entrance_south", "Cargo Garage", EXTERIOR, NONE, 14), ("south_fuel_depot", "Fuel Depot", UTILITY, NONE, 10),
                      ("south_garage", "Vehicle Bay", OFFICE, NONE, 12), ("south_stores", "Stores", OFFICE, NONE, 10)])
room("pad_south", "South Pad", OUTDOOR, NONE, (48, 136, 50, 8))

# west: Research. A corridor with labs either side ending in a vertical concourse and the way in at the back
room("west_corridor", "West Corridor", CORRIDOR, NONE, (26, 66, 38, 6), (20, 48, 6, 43))
stack_x(26, 52, 14, [("west_vault", "Vault", ITEM, NONE, 10), ("doors_west", "West Door Control", UTILITY, DOORS, 8), ("west_records", "Records", ITEM, NONE, 10), ("west_server", "Server Room", UTILITY, NONE, 8)])
stack_x(26, 72, 12, [("west_lights", "Light Control", UTILITY, LIGHTS, 12), ("west_lab_b", "Lab B", OFFICE, NONE, 12), ("spawn_west", "Staff Lounge", OFFICE, NONE, 14)])
stack_y(8, 48, 12, [("west_lobby", "Research Lobby", OFFICE, NONE, 11), ("entrance_west", "Service Tunnel", EXTERIOR, NONE, 12), ("west_lab_a", "Lab A", OFFICE, NONE, 10),
                    ("west_boat_house", "Boat House", OFFICE, NONE, 10)])
room("pad_west", "West Pad", OUTDOOR, NONE, (0, 59, 8, 12))

# the four corners, each a block of its own with a corridor that branches (4 m wide, off the 6 m main corridors) and rooms off every branch.
# NW, Administration: an archive and offices, reached from the north and west corridors
room("nw_corridor", "NW Corridor", CORRIDOR, NONE, (34, 12, 4, 36), (38, 24, 14, 4), (38, 36, 14, 4))
stack_y(20, 12, 14, [("nw_archive", "Archive Stacks", ITEM, NONE, 10), ("nw_files", "Filing Room", OFFICE, NONE, 8), ("nw_hr", "HR Office", OFFICE, NONE, 10), ("nw_mail", "Mail Room", OFFICE, NONE, 8)])
stack_x(38, 12, 12, [("nw_conference", "Conference Room", OFFICE, NONE, 8), ("nw_director", "Director's Office", OFFICE, NONE, 6)])
stack_x(38, 28, 8, [("nw_accounts", "Accounts", OFFICE, NONE, 7), ("nw_kitchen", "Staff Kitchen", OFFICE, NONE, 7)])
stack_x(38, 40, 8, [("nw_supply", "Supply Closet", UTILITY, NONE, 8), ("nw_print", "Print Room", OFFICE, NONE, 6)])
# SW, Warehouse: receiving, stores and workshops, reached from the west and south corridors
room("sw_corridor", "SW Corridor", CORRIDOR, NONE, (24, 91, 4, 45), (28, 106, 16, 4), (28, 122, 16, 4))
stack_y(8, 91, 16, [("sw_receiving", "Receiving Bay", OFFICE, NONE, 12), ("sw_cold_store", "Cold Storage", UTILITY, NONE, 11), ("sw_parts", "Parts Warehouse", OFFICE, NONE, 12),
                    ("sw_tool_crib", "Tool Crib", OFFICE, NONE, 10)])
stack_x(28, 91, 15, [("sw_battery", "Battery Room", UTILITY, NONE, 9), ("sw_compressor", "Compressor Room", UTILITY, NONE, 7)])
stack_x(28, 110, 12, [("sw_paint", "Paint Shop", OFFICE, NONE, 8), ("sw_welding", "Welding Shop", OFFICE, NONE, 8)])
stack_x(28, 126, 10, [("sw_dispatch", "Dispatch", OFFICE, NONE, 8), ("sw_lounge", "Driver Lounge", OFFICE, NONE, 8)])
# NE, Aviation: the helipad hangar and everything that serves it. Only the east wing leads here, so the ways out are a long way from the ways in
room("ne_corridor", "NE Corridor", CORRIDOR, NONE, (106, 22, 52, 4), (142, 26, 4, 20), (106, 34, 36, 4))
room("extract_helipad", "Helipad Hangar", EXTERIOR, NONE, (112, 4, 34, 18))
stack_y(106, 4, 6, [("ne_fuel_bunker", "Fuel Bunker", UTILITY, NONE, 9), ("ne_flight_ops", "Flight Ops", OFFICE, NONE, 9)])
stack_y(146, 4, 12, [("ne_radio", "Radio Room", UTILITY, NONE, 9), ("ne_briefing", "Pilot Briefing", OFFICE, NONE, 9)])
stack_x(106, 26, 8, [("ne_stores_a", "Aviation Stores", OFFICE, NONE, 12), ("ne_stores_b", "Hangar Stores", OFFICE, NONE, 12), ("ne_tools", "Tool Room", OFFICE, NONE, 12)])
stack_x(106, 38, 8, [("ne_crew_a", "Crew Room A", OFFICE, NONE, 12), ("ne_crew_b", "Crew Room B", OFFICE, NONE, 12), ("ne_lockers", "Pilot Lockers", OFFICE, NONE, 12)])
stack_y(146, 26, 12, [("ne_ops", "Operations", OFFICE, NONE, 10), ("ne_security", "Hangar Security", UTILITY, NONE, 10)])
room("pad_helipad", "Helipad", OUTDOOR, NONE, (112, 0, 34, 4))
# SE, Rail and cargo: freight bays either side of two corridors that cross a third. Only the east wing leads here too
room("se_corridor", "SE Corridor", CORRIDOR, NONE, (102, 108, 56, 4), (120, 93, 4, 43), (142, 93, 4, 43))
stack_x(102, 93, 15, [("se_freight_office", "Freight Office", OFFICE, NONE, 9), ("se_customs", "Customs", OFFICE, NONE, 9)])
stack_x(124, 93, 15, [("se_container_store", "Container Store", OFFICE, NONE, 9), ("se_weigh_station", "Weigh Station", UTILITY, NONE, 9)])
room("se_rail_office", "Rail Office", OFFICE, NONE, (146, 93, 12, 15))
stack_y(102, 112, 18, [("se_bay_1", "Freight Bay 1", OFFICE, NONE, 12), ("se_bay_2", "Freight Bay 2", OFFICE, NONE, 12)])
stack_y(124, 112, 18, [("se_bay_3", "Freight Bay 3", OFFICE, NONE, 12), ("se_tank_room", "Tank Room", UTILITY, NONE, 12)])
stack_y(146, 112, 12, [("se_switch_room", "Switch Room", UTILITY, NONE, 12), ("se_loco_shed", "Loco Shed", OFFICE, NONE, 12)])
# the gaps between the wings and the corner blocks, filled the same way
stack_y(52, 28, 10, [("nn_chase", "Service Chase", UTILITY, NONE, 8), ("nn_janitor", "Janitor Closet", UTILITY, NONE, 8), ("nn_core", "Utility Core", UTILITY, NONE, 8)])  # between the NW block and the armory
room("link_corridor", "West Link Corridor", CORRIDOR, NONE, (26, 48, 26, 4))  # joins the NW block, the west corridor and the labs
room("sw_link", "SW Link Corridor", CORRIDOR, NONE, (44, 84, 4, 36))  # between the SW block and the barracks
stack_y(48, 84, 8, [("sl_boiler", "Boiler Room", UTILITY, NONE, 12), ("sl_linen", "Linen Store", OFFICE, NONE, 12), ("sl_workshop", "Maintenance Workshop", OFFICE, NONE, 12)])
room("ss_link", "South Service Corridor", CORRIDOR, NONE, (90, 87, 4, 33))  # between the cafeteria and the rail block
stack_y(94, 87, 8, [("ss_truck_bay", "Truck Bay", OFFICE, NONE, 11), ("ss_wash_bay", "Wash Bay", OFFICE, NONE, 11), ("ss_tyre_store", "Tyre Store", OFFICE, NONE, 11)])
room("east_service", "East Service Corridor", CORRIDOR, NONE, (102, 87, 38, 6))  # under the east wing, over the rail block
stack_y(92, 28, 14, [("na_offices", "Admin Offices", OFFICE, NONE, 8), ("na_comms", "Comms Room", UTILITY, NONE, 8), ("na_records", "Annex Records", ITEM, NONE, 8)])  # beside the camera room

# ------------------------------------------------------------------ spacing: the four corner blocks stand off from the wings, so the walls between neighbours are streets, not shared
SPACING = 8  # modules (m) each corner block moves out, along both axes
for rid in ROOMS:
    if rid in ("sw_link",):
        continue  # a link between the SW block and the barracks stays where it was
    dx, dy = (-SPACING, -SPACING) if rid.startswith("nw_") else (-SPACING, SPACING) if rid.startswith("sw_") else \
             (SPACING, -SPACING) if rid.startswith("ne_") or rid in ("extract_helipad", "pad_helipad") else (SPACING, SPACING) if rid.startswith("se_") else (0, 0)
    if dx or dy:
        ROOMS[rid]["rects"] = [(x + dx, y + dy, w, h) for x, y, w, h in ROOMS[rid]["rects"]]

# the streets the spacing opened are filled with rooms (coordinates are the moved blocks')
# NW block: south edge and east edge
room("nw_press", "Press Room", OFFICE, NONE, (8, 40, 12, 8)); room("nw_reception", "Reception", OFFICE, NONE, (30, 40, 14, 8))
room("nw_gate_post", "Gate Post", OFFICE, NONE, (44, 4, 8, 8)); room("nw_valet", "Valet Lockers", OFFICE, NONE, (44, 16, 8, 12))
room("nw_depot", "Delivery Depot", OFFICE, NONE, (44, 28, 8, 8)); room("nw_spares", "Spare Parts", UTILITY, NONE, (44, 36, 8, 8))
# NE block: west edge and south edge
room("ne_guard_shack", "Guard Shack", OFFICE, NONE, (106, -4, 8, 9)); room("ne_supply_shed", "Supply Shed", OFFICE, NONE, (106, 5, 8, 9))
room("ne_west_gate", "West Gate", OFFICE, NONE, (106, 18, 8, 12)); room("ne_west_lockers", "Ground Crew Lockers", OFFICE, NONE, (106, 30, 8, 8))
stack_x(114, 38, 14, [("ne_ground_support", "Ground Support", OFFICE, NONE, 12), ("ne_fuel_pumps", "Fuel Pumps", UTILITY, NONE, 14)])
room("ne_checkpoint", "Checkpoint", OFFICE, NONE, (140, 38, 6, 8)); room("ne_plant_gate", "Plant Gate", OFFICE, NONE, (146, 38, 8, 8))
# SE block: north edge
room("se_gatehouse", "Rail Gatehouse", OFFICE, NONE, (110, 93, 18, 8)); room("se_scale_house", "Scale House", OFFICE, NONE, (132, 93, 18, 8))
# SW block: north edge and east edge
room("sw_watch_post", "Watch Post", OFFICE, NONE, (14, 91, 6, 8)); room("sw_overlook", "Yard Overlook", OFFICE, NONE, (20, 91, 24, 8))
room("sw_east_store", "East Store", OFFICE, NONE, (36, 99, 8, 15)); room("sw_east_bay", "East Bay", OFFICE, NONE, (36, 118, 8, 12))
room("sw_east_garage", "Equipment Garage", OFFICE, NONE, (36, 130, 8, 14))
# two roads round the outside that join far apart parts of the campus: the east one links the aviation and rail blocks past the pad, the south one links the warehouse, the south pad and the rail block
room("east_road", "East Perimeter Road", CORRIDOR, NONE, (166, 32, 4, 90))
room("south_road", "South Perimeter Road", CORRIDOR, NONE, (0, 144, 166, 4))

ARTIFACTS = ["north_armory", "north_evidence", "east_generator", "south_cafeteria", "west_vault", "west_records"]  # one marker in each (there are six artifacts)

# ------------------------------------------------------------------ doors: pairs of rooms that get a door where they share a wall (two if the wall is long)
PAIRS = []


def connect(a, *others):
    for b in others:
        PAIRS.append((a, b))


connect("north_corridor", "north_armory", "north_evidence", "north_interview", "doors_north", "north_cameras", "north_turrets", "north_lockers", "spawn_north",
        "entrance_garage", "entrance_north", "north_registry", "north_briefing", "north_annex")
connect("north_armory", "north_evidence"); connect("north_interview", "doors_north"); connect("north_cameras", "north_turrets"); connect("north_lockers", "spawn_north")
connect("entrance_garage", "entrance_north"); connect("north_registry", "north_briefing")
connect("entrance_north", "pad_north"); connect("entrance_garage", "pad_north")
connect("spawn_north", "atrium"); connect("doors_north", "atrium"); connect("doors_north", "west_server")

connect("east_corridor", "doors_east", "east_generator", "east_breakers", "spawn_east", "east_workshop", "east_stores", "east_pump_house", "east_plant_office", "extract_east",
        "east_cold_store", "extract_rail")
connect("doors_east", "east_generator"); connect("east_generator", "east_breakers"); connect("spawn_east", "east_workshop"); connect("east_workshop", "east_stores")
connect("east_stores", "east_pump_house"); connect("extract_east", "east_plant_office"); connect("east_cold_store", "extract_rail")
connect("extract_east", "pad_east"); connect("extract_rail", "pad_east"); connect("extract_helipad", "pad_helipad")
connect("spawn_east", "atrium"); connect("doors_east", "atrium")

connect("south_corridor", "spawn_south", "doors_south", "south_dormitory", "south_break_room", "south_cafeteria", "south_infirmary", "entrance_service", "entrance_south",
        "south_fuel_depot", "south_garage", "south_stores")
connect("south_dormitory", "doors_south"); connect("south_break_room", "south_cafeteria"); connect("south_cafeteria", "south_infirmary"); connect("entrance_service", "entrance_south")
connect("south_fuel_depot", "south_garage"); connect("south_garage", "south_stores")
connect("entrance_south", "pad_south"); connect("entrance_service", "pad_south")
connect("spawn_south", "atrium"); connect("south_break_room", "atrium")

connect("west_corridor", "west_vault", "doors_west", "west_records", "west_server", "west_lights", "west_lab_b", "spawn_west", "west_lobby", "entrance_west", "west_lab_a", "west_boat_house")
connect("west_vault", "doors_west"); connect("west_records", "west_server"); connect("west_lights", "west_lab_b"); connect("west_lab_b", "spawn_west")
connect("entrance_west", "west_lab_a"); connect("west_lab_a", "west_boat_house")
connect("entrance_west", "pad_west"); connect("spawn_west", "atrium")

# the corner blocks
connect("nw_corridor", "nw_archive", "nw_files", "nw_hr", "nw_mail", "nw_conference", "nw_director", "nw_accounts", "nw_kitchen", "nw_supply", "nw_print")
connect("nw_archive", "nw_files"); connect("nw_hr", "nw_mail"); connect("nw_conference", "nw_director"); connect("nw_accounts", "nw_kitchen"); connect("nw_supply", "nw_print")
connect("nw_mail", "west_corridor"); connect("nw_director", "entrance_garage")
connect("sw_corridor", "sw_receiving", "sw_cold_store", "sw_parts", "sw_tool_crib", "sw_battery", "sw_compressor", "sw_paint", "sw_welding", "sw_dispatch", "sw_lounge")
connect("sw_receiving", "sw_cold_store"); connect("sw_parts", "sw_tool_crib"); connect("sw_battery", "sw_compressor"); connect("sw_paint", "sw_welding"); connect("sw_dispatch", "sw_lounge")
connect("sw_corridor", "west_corridor"); connect("sw_receiving", "west_boat_house"); connect("sw_lounge", "entrance_service")
connect("ne_corridor", "extract_helipad", "ne_flight_ops", "ne_briefing", "ne_stores_a", "ne_stores_b", "ne_tools", "ne_crew_a", "ne_crew_b", "ne_lockers", "ne_ops", "ne_security")
connect("ne_fuel_bunker", "ne_flight_ops"); connect("ne_radio", "ne_briefing"); connect("ne_stores_a", "ne_stores_b"); connect("ne_stores_b", "ne_tools"); connect("ne_crew_a", "ne_crew_b")
connect("ne_crew_b", "ne_lockers"); connect("ne_ops", "ne_security"); connect("ne_security", "east_plant_office")
connect("ne_corridor", "east_corridor")
connect("se_corridor", "se_freight_office", "se_customs", "se_container_store", "se_weigh_station", "se_rail_office", "se_bay_1", "se_bay_2", "se_bay_3", "se_tank_room", "se_switch_room", "se_loco_shed")
connect("se_freight_office", "se_customs"); connect("se_container_store", "se_weigh_station"); connect("se_bay_1", "se_bay_2"); connect("se_bay_3", "se_tank_room"); connect("se_switch_room", "se_loco_shed")
connect("se_rail_office", "extract_rail"); connect("se_corridor", "east_corridor")

# the gap fillers. None of them joins the east to the entrance side except through the east wing's own corridors, so the ways in stay a long way from the ways out
connect("nn_chase", "north_corridor", "nn_janitor", "nw_kitchen"); connect("nn_janitor", "nn_core", "nw_corridor"); connect("nn_core", "nw_print", "west_server")
connect("link_corridor", "nw_mail", "nw_corridor", "doors_west", "west_records", "nn_core")
connect("sw_link", "sl_boiler", "sl_linen", "sl_workshop", "west_lab_b", "south_corridor", "sw_corridor"); connect("sl_boiler", "sl_linen"); connect("sl_linen", "sl_workshop")
connect("ss_link", "ss_truck_bay", "ss_wash_bay", "ss_tyre_store", "south_corridor", "south_cafeteria", "south_break_room"); connect("ss_truck_bay", "ss_wash_bay"); connect("ss_wash_bay", "ss_tyre_store")
connect("ss_tyre_store", "south_corridor")
connect("east_service", "east_workshop", "east_stores", "east_pump_house", "se_corridor")
connect("na_offices", "north_corridor", "na_comms"); connect("na_comms", "na_records", "north_cameras"); connect("na_records", "north_turrets")

# the new rooms and roads
connect("nw_press", "nw_mail", "west_lobby"); connect("nw_reception", "nw_supply", "nw_print", "link_corridor")
connect("nw_gate_post", "nw_director"); connect("nw_valet", "entrance_garage", "nw_corridor"); connect("nw_depot", "nn_chase", "nw_corridor"); connect("nw_spares", "nn_janitor", "nw_print")
connect("ne_guard_shack", "ne_fuel_bunker"); connect("ne_supply_shed", "ne_flight_ops"); connect("ne_west_gate", "ne_stores_a", "ne_corridor")
connect("ne_west_lockers", "ne_crew_a")
connect("ne_ground_support", "ne_crew_a", "east_generator"); connect("ne_fuel_pumps", "ne_crew_b", "ne_lockers", "east_generator", "east_breakers", "ne_checkpoint")
connect("ne_checkpoint", "ne_lockers", "east_corridor"); connect("ne_plant_gate", "ne_corridor", "east_plant_office")
connect("se_gatehouse", "east_service", "se_freight_office", "se_customs"); connect("se_scale_house", "east_service", "se_container_store", "se_weigh_station")
connect("sw_watch_post", "west_boat_house", "sw_corridor"); connect("sw_overlook", "west_corridor", "sw_battery", "sw_compressor")
connect("sw_east_store", "sw_compressor", "sw_link"); connect("sw_east_bay", "sw_welding", "sw_link"); connect("sw_east_garage", "sw_lounge", "entrance_service")
connect("east_road", "ne_security", "pad_east", "se_rail_office", "se_switch_room")
connect("south_road", "sw_tool_crib", "sw_dispatch", "sw_lounge", "pad_south", "se_bay_2", "se_tank_room", "se_loco_shed")
GATES = ["north_corridor", "east_corridor", "south_corridor", "west_corridor"]  # each meets the atrium through two doors side by side: the wing gate
DOUBLE = [("nw_corridor", "north_corridor"), ("sw_corridor", "south_corridor"), ("ne_corridor", "east_corridor"), ("se_corridor", "east_corridor"),
          ("link_corridor", "west_corridor"), ("east_service", "east_corridor")]  # a branch corridor joins a main one through two doors
PAIRS = [p for p in PAIRS if p not in DOUBLE]
LINK_WIDTH = 4  # modules, the width of a link corridor


def gap_between(a, b):
    """the nearest facing edges of two rooms that do not touch: (gap in modules, 'x' | 'y', start of the overlap, end of the overlap, edge a, edge b), or None"""
    best = None
    for ra in ROOMS[a]["rects"]:
        for rb in ROOMS[b]["rects"]:
            ax, ay, aw, ah = ra; bx, by, bw, bh = rb
            lo, hi = max(ay, by), min(ay + ah, by + bh)  # side by side
            if hi - lo >= LINK_WIDTH:
                gap = bx - (ax + aw) if bx >= ax + aw else ax - (bx + bw) if ax >= bx + bw else None
                if gap is not None and (best is None or gap < best[0]): best = (gap, "x", lo, hi, ax + aw if bx >= ax + aw else bx + bw)
            lo, hi = max(ax, bx), min(ax + aw, bx + bw)  # one over the other
            if hi - lo >= LINK_WIDTH:
                gap = by - (ay + ah) if by >= ay + ah else ay - (by + bh) if ay >= by + bh else None
                if gap is not None and (best is None or gap < best[0]): best = (gap, "y", lo, hi, ay + ah if by >= ay + ah else by + bh)
    return best


def link_rooms(a, b):
    """a link corridor in the gap between two rooms that no longer touch: the pairs it gives (a, link) and (link, b)"""
    g = gap_between(a, b)
    if g is None:
        print("no straight link between %s and %s: that door is left out" % (a, b))
        return []
    gap, axis, lo, hi, edge = g
    mid = (lo + hi) // 2 - LINK_WIDTH // 2
    rid = "link_%s_%s" % (a, b)
    rect = (edge, mid, gap, LINK_WIDTH) if axis == "x" else (mid, edge, LINK_WIDTH, gap)
    if rid in ROOMS or any(rect[0] < x + w and x < rect[0] + rect[2] and rect[1] < y + h and y < rect[1] + rect[3] for r in ROOMS.values() for x, y, w, h in r["rects"]):
        print("a link between %s and %s would run through another room: that door is left out" % (a, b))
        return []
    room(rid, "Link Passage", CORRIDOR, NONE, rect)
    return [(a, rid), (rid, b)]


def relink(pairs):
    out = []
    for a, b in pairs:
        out += [(a, b)] if shared(a, b) is not None else link_rooms(a, b)
    return out




def cell_rect(m):
    x, y, w, h = m
    return (4 * x, 4 * y, 4 * w - 1, 4 * h - 1)


def shared(a, b):
    """the wall between two rooms: ('h' | 'v', gap line in cells, first and last cell along it), the longest, or None"""
    best = None
    for ra in ROOMS[a]["rects"]:
        for rb in ROOMS[b]["rects"]:
            ax, ay, aw, ah = cell_rect(ra); bx, by, bw, bh = cell_rect(rb)
            if bx == ax + aw + 1 or ax == bx + bw + 1:  # side by side, a wall column between
                lo, hi = max(ay, by), min(ay + ah - 1, by + bh - 1)
                if hi - lo + 1 >= 4:
                    cand = ("v", ax + aw if bx > ax else bx + bw, lo, hi)
                    if best is None or hi - lo > best[3] - best[2]: best = cand
            if by == ay + ah + 1 or ay == by + bh + 1:  # one above the other, a wall row between
                lo, hi = max(ax, bx), min(ax + aw - 1, bx + bw - 1)
                if hi - lo + 1 >= 4:
                    cand = ("h", ay + ah if by > ay else by + bh, lo, hi)
                    if best is None or hi - lo > best[3] - best[2]: best = cand
    return best


PAIRS = relink(PAIRS)
GATE_PAIRS = relink([(g, "atrium") for g in GATES])
DOUBLE_PAIRS = relink(DOUBLE)
doors = []
seen_pairs = set()
for a, b in PAIRS:
    if (a, b) in seen_pairs or (b, a) in seen_pairs:
        sys.exit("pair twice: %s %s" % (a, b))
    seen_pairs.add((a, b))
    wall = shared(a, b)
    if wall is None:
        sys.exit("no wall long enough for a door between %s and %s" % (a, b))
    kind, gap, lo, hi = wall
    length = hi - lo + 1
    for s in ([round((lo + hi) / 2 - 1.5)] if length < 40 else [round(lo + length * 0.28 - 1.5), round(lo + length * 0.72 - 1.5)]):
        doors.append(dict(a=a, b=b, kind=kind, gap=gap, start=s))
for a, b in [p for p in GATE_PAIRS + DOUBLE_PAIRS if shared(*p) and shared(*p)[3] - shared(*p)[2] >= 8]:  # the wing gates and the branch corridors: two doors side by side where the wall is long enough
    wall = shared(a, b)
    if wall is None:
        sys.exit("no wall for the gate between %s and %s" % (a, b))
    kind, gap, lo, hi = wall
    mid = (lo + hi) // 2
    for s in (mid - 4, mid):  # two gates of 4 cells, side by side, in the middle of the wall they share
        doors.append(dict(a=a, b=b, kind=kind, gap=gap, start=s))

# ------------------------------------------------------------------ checks
floor = {}  # cell -> room, over the rooms' rectangles
for rid, r in ROOMS.items():
    for m in r["rects"]:
        x, y, w, h = cell_rect(m)
        for cy in range(y, y + h):
            for cx in range(x, x + w):
                if floor.get((cx, cy), rid) != rid:  # (one room's own rectangles may cross, like a corridor that crosses another)
                    sys.exit("%s overlaps %s at module %d,%d" % (rid, floor[(cx, cy)], cx // 4, cy // 4))
                floor[(cx, cy)] = rid
for d in doors:
    if d["kind"] == "h":
        first, second = (d["start"] + 1, d["gap"] - 1), (d["start"] + 1, d["gap"] + 1); cells = [(d["start"] + i, d["gap"]) for i in range(4)]
    else:
        first, second = (d["gap"] - 1, d["start"] + 1), (d["gap"] + 1, d["start"] + 1); cells = [(d["gap"], d["start"] + i) for i in range(4)]
    if {floor.get(first), floor.get(second)} != {d["a"], d["b"]}:
        sys.exit("door %s/%s lands between %s" % (d["a"], d["b"], {floor.get(first), floor.get(second)}))
    if any(c in floor for c in cells):
        sys.exit("door %s/%s sits on floor" % (d["a"], d["b"]))
    d["name"] = "Door_%s_%s" % (d["a"], d["b"])
count = {}
for d in doors:
    n = count.get(d["name"], 0); count[d["name"]] = n + 1
    if n: d["name"] += "_%d" % (n + 1)
    d["pos"] = (d["start"] * TILE + 2 * TILE, d["gap"] * TILE + TILE / 2) if d["kind"] == "h" else (d["gap"] * TILE + TILE / 2, d["start"] * TILE + 2 * TILE)

adj = {rid: set() for rid in ROOMS}
for d in doors:
    adj[d["a"]].add(d["b"]); adj[d["b"]].add(d["a"])
reach, queue = {"atrium"}, deque(["atrium"])
while queue:
    for n in adj[queue.popleft()]:
        if n not in reach: reach.add(n); queue.append(n)
if reach != set(ROOMS):
    sys.exit("cannot be reached from the atrium: %s" % sorted(set(ROOMS) - reach))


def centre(rid):
    parts = [(cell_rect(m)[0] + cell_rect(m)[2] / 2, cell_rect(m)[1] + cell_rect(m)[3] / 2, cell_rect(m)[2] * cell_rect(m)[3]) for m in ROOMS[rid]["rects"]]
    total = sum(p[2] for p in parts)
    return (sum(p[0] * p[2] for p in parts) / total * 0.25, sum(p[1] * p[2] for p in parts) / total * 0.25)  # metres


def walk(src):
    """shortest walking distance in metres from the middle of a room to the middle of every room (door to door through each room)"""
    best, heap = {}, [(0.0, src, None)]
    while heap:
        dd, rid, via = heapq.heappop(heap)
        if best.get(rid, 1e9) <= dd:
            continue
        best[rid] = dd
        here = via if via else centre(rid)
        for d in doors:
            if rid not in (d["a"], d["b"]):
                continue
            other = d["b"] if d["a"] == rid else d["a"]
            p = (d["pos"][0] / TILE * 0.25, d["pos"][1] / TILE * 0.25)
            heapq.heappush(heap, (dd + math.dist(here, p), other, p))
    return best


spawns = sorted(r for r in ROOMS if r.startswith("spawn_"))
entrances = sorted(r for r in ROOMS if r.startswith("entrance_"))
extracts = sorted(r for r in ROOMS if r.startswith("extract_"))
area = {rid: sum(m[2] * m[3] for m in r["rects"]) for rid, r in ROOMS.items()}
outdoor = sum(a for rid, a in area.items() if ROOMS[rid]["kind"] == OUTDOOR)
xs = [cell_rect(m)[0] for r in ROOMS.values() for m in r["rects"]] + [cell_rect(m)[0] + cell_rect(m)[2] for r in ROOMS.values() for m in r["rects"]]
ys = [cell_rect(m)[1] for r in ROOMS.values() for m in r["rects"]] + [cell_rect(m)[1] + cell_rect(m)[3] for r in ROOMS.values() for m in r["rects"]]
print("rooms: %d   doors: %d   floor: %d m2 (%d indoors, %d outdoors)   %d cells" % (len(ROOMS), len(doors), sum(area.values()), sum(area.values()) - outdoor, outdoor, sum(area.values()) * 16))
print("size: %.0f x %.0f m" % ((max(xs) - min(xs) + 2) / 4, (max(ys) - min(ys) + 2) / 4))
print("walking distance in metres (door to door, through the rooms)")
print("%-18s" % "" + "".join("%-17s" % e[8:] for e in extracts))
for group in (spawns, entrances):
    for s in group:
        w = walk(s)
        print("%-18s" % s + "".join("%-17d" % w[e] for e in extracts))

# ------------------------------------------------------------------ the scene
lines = ["[gd_scene format=3]", "",
         '[ext_resource type="Script" path="res://game/environment/facility_map.gd" id="1_map"]',
         '[ext_resource type="Script" path="res://game/environment/facility_room.gd" id="3_room"]',
         '[ext_resource type="PackedScene" path="res://game/environment/facility_door.tscn" id="4_door"]',
         '[ext_resource type="PackedScene" path="res://game/utility/door_control_panel.tscn" id="6_panel"]',
         '[ext_resource type="Script" path="res://game/pickups/artifact_location.gd" id="7_loc"]',
         '[ext_resource type="Script" path="res://game/environment/facility_room_rect.gd" id="rect_script"]', "",
         '[node name="FacilityMap" type="Node2D"]', "texture_filter = 4", 'script = ExtResource("1_map")', "",
         '[node name="Rooms" type="Node2D" parent="."]', ""]


def rect_node(parent, name, x, y, w, h):
    return ['[node name="%s" type="Control" parent="Rooms/%s"]' % (name, parent), "custom_minimum_size = Vector2(11, 11)", "layout_mode = 3", "anchors_preset = 0",
            "offset_left = %d.0" % (x * TILE), "offset_top = %d.0" % (y * TILE), "offset_right = %d.0" % ((x + w) * TILE), "offset_bottom = %d.0" % ((y + h) * TILE),
            "mouse_filter = 2", 'script = ExtResource("rect_script")', ""]


for rid, r in ROOMS.items():
    lines += ['[node name="%s" type="Node2D" parent="Rooms"]' % rid, 'script = ExtResource("3_room")', 'display_name = "%s"' % r["name"], "kind = %d" % r["kind"]]
    if r["function"]:
        lines.append("function = %d" % r["function"])
    lines.append("")
    for i, m in enumerate(r["rects"]):
        lines += rect_node(rid, "Rect%d" % (i + 1), *cell_rect(m))
    bridges = 0
    for i, ma in enumerate(r["rects"]):  # a room of several rectangles (a corridor that turns) is joined across the wall cell between them
        for mb in r["rects"][i + 1:]:
            ax, ay, aw, ah = cell_rect(ma); bx, by, bw, bh = cell_rect(mb)
            if bx == ax + aw + 1 or ax == bx + bw + 1:
                lo, hi = max(ay, by), min(ay + ah - 1, by + bh - 1)
                if hi >= lo:
                    bridges += 1; lines += rect_node(rid, "Bridge%d" % bridges, ax + aw if bx > ax else bx + bw, lo, 1, hi - lo + 1)
            if by == ay + ah + 1 or ay == by + bh + 1:
                lo, hi = max(ax, bx), min(ax + aw - 1, bx + bw - 1)
                if hi >= lo:
                    bridges += 1; lines += rect_node(rid, "Bridge%d" % bridges, lo, ay + ah if by > ay else by + bh, hi - lo + 1, 1)
lines += ['[node name="Doors" type="Node2D" parent="."]', "z_index = 1", ""]
for d in doors:
    lines += ['[node name="%s" parent="Doors" instance=ExtResource("4_door")]' % d["name"], "position = Vector2(%g, %g)" % d["pos"]]
    if d["kind"] == "v":
        lines.append("horizontal = false")
    lines.append("")
lines += ['[node name="Vents" type="Node2D" parent="."]', "",
          '[node name="ArtifactLocations" type="Node2D" parent="."]', ""]
for rid in ARTIFACTS:
    cx, cy = centre(rid)
    lines += ['[node name="%sArtifact" type="Marker2D" parent="ArtifactLocations"]' % "".join(p.capitalize() for p in rid.split("_")),
              "position = Vector2(%d, %d)" % (cx / 0.25 * TILE, cy / 0.25 * TILE), 'script = ExtResource("7_loc")', ""]
lines += ['[node name="Props" type="Node2D" parent="."]', "y_sort_enabled = true", ""]
for rid in sorted(r for r in ROOMS if r.startswith("doors_")):  # each wing's door panel, against the room's north wall
    x, y, w, h = cell_rect(ROOMS[rid]["rects"][0])
    lines += ['[node name="DoorControlPanel_%s" parent="Props" instance=ExtResource("6_panel")]' % rid[6:], "position = Vector2(%d, %d)" % ((x + w / 2) * TILE, y * TILE + 24), ""]
lines += ['[node name="Decor" type="Node2D" parent="."]', "y_sort_enabled = true", "",
          '[node name="Actors" type="Node2D" parent="."]', "y_sort_enabled = true", ""]
open(OUT_SCENE, "w", newline="\n").write("\n".join(lines))
print("wrote", OUT_SCENE)

# ------------------------------------------------------------------ the picture
try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit(0)
S = 8  # px per metre
x0 = min(m[0] for r in ROOMS.values() for m in r["rects"]); y0 = min(m[1] for r in ROOMS.values() for m in r["rects"])
x1 = max(m[0] + m[2] for r in ROOMS.values() for m in r["rects"]); y1 = max(m[1] + m[3] for r in ROOMS.values() for m in r["rects"])
img = Image.new("RGB", ((x1 - x0) * S + 40 + 230, (y1 - y0) * S + 40), "#0d1117")
dr = ImageDraw.Draw(img)
OX, OY = 20 - x0 * S, 20 - y0 * S
for rid, r in ROOMS.items():
    col = KIND_COLOURS[r["kind"]]
    for m in r["rects"]:
        x, y, w, h = m
        dr.rectangle((OX + x * S, OY + y * S, OX + (x + w) * S - 1, OY + (y + h) * S - 1), fill=tuple(int(int(col[i:i + 2], 16) * 0.3 + 13 * 0.7) for i in (1, 3, 5)), outline=col)
for rid, r in ROOMS.items():
    x, y, w, h = max(r["rects"], key=lambda m: m[2] * m[3])
    lines_ = []
    for wd in r["name"].split():
        if lines_ and len(lines_[-1]) + len(wd) < max(6, int(w * S / 6.5)): lines_[-1] += " " + wd
        else: lines_.append(wd)
    ty = OY + (y + h / 2) * S - 6 * len(lines_)
    for ln in lines_:
        dr.text((OX + (x + w / 2) * S - len(ln) * 3, ty), ln, fill="#e7e3d8"); ty += 12
badge = {"spawn_": ("S", "#4be38a"), "entrance_": ("E", "#e5484d"), "extract_": ("X", "#f2b544"), "doors_": ("D", "#6fd3e8")}
for rid, r in ROOMS.items():
    for pre, (letter, col) in badge.items():
        if rid.startswith(pre):
            x, y, w, h = r["rects"][0]
            cx, cy = OX + x * S + 10, OY + y * S + 10
            dr.ellipse((cx - 8, cy - 8, cx + 8, cy + 8), fill=col); dr.text((cx - 3, cy - 6), letter, fill="#0d1117")
for d in doors:
    px, py = d["pos"][0] / TILE * 0.25 * S, d["pos"][1] / TILE * 0.25 * S
    if d["kind"] == "h": dr.rectangle((OX + px - S / 2, OY + py - 2, OX + px + S / 2, OY + py + 2), fill="#ffffff")
    else: dr.rectangle((OX + px - 2, OY + py - S / 2, OX + px + 2, OY + py + S / 2), fill="#ffffff")
for rid in ARTIFACTS:
    cx, cy = centre(rid)
    dr.regular_polygon((OX + cx * S, OY + cy * S + 12, 5), 4, fill="#c9a0ff")
lx = (x1 - x0) * S + 40
for i, t in enumerate(["NIGHT SHIFT - campus plan", "", "1 m = %d px" % S, "", "S  guard spawn room", "E  intruder entrance", "X  extract room", "D  wing door panel", "<> artifact spot", "white bar: a door",
                       "", "room kind:", "blue-grey corridor", "cyan utility / console", "violet item room", "green office", "amber exterior room", "grey outdoors"]):
    dr.text((lx, 20 + i * 16), t, fill="#e7e3d8")
os.makedirs(os.path.dirname(OUT_PLAN), exist_ok=True)
img.save(OUT_PLAN)
print("wrote", OUT_PLAN)
