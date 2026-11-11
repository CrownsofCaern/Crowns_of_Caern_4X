class_name ComputerPlayers
extends RefCounted
## Runs computer players' turns through the strategic AI, which acts only
## through GameSession commands.


## Plays every computer turn until a human player is to move or the game ends.
## Returns the number of turns played.
static func play(session: GameSession, max_turns: int = 64) -> int:
	return StrategicAI.play_ai_turns(session, max_turns)
