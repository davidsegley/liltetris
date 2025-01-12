class_name KickWallTable
extends RefCounted

# Pieces kick wall
# Check https://tetris.wiki/Super_Rotation_System

# J, L, S, T, Z
const COMMON := [
	[Vector2(0, 0), Vector2(0, 0), Vector2(0, 0), Vector2(0, 0), Vector2(0, 0)], # 0
	[Vector2(0, 0), Vector2(1, 0), Vector2(1, -1), Vector2(0, 2), Vector2(1, 2)], # R
	[Vector2(0, 0), Vector2(0, 0), Vector2(0, 0), Vector2(0, 0), Vector2(0, 0)], # 2
	[Vector2(0, 0), Vector2(-1, 0), Vector2(-1, -1), Vector2(0, 2), Vector2(-1, 2)], # L
]

# I piece
const OTHER := [
	[Vector2(0, 0), Vector2(-1, 0), Vector2(2, 0), Vector2(-1, 0), Vector2(2, 0)], # 0
	[Vector2(-1, 0), Vector2(0, 0), Vector2(0, 0), Vector2(0, 1), Vector2(0, -2)], # R
	[Vector2(-1, 1), Vector2(1, 1), Vector2(-2, 1), Vector2(1, 0), Vector2(-2, 0)], # 2
	[Vector2(0, 1), Vector2(0, 1), Vector2(0, 1), Vector2(0, -1), Vector2(0, 2)], # L
]
