## A base class for a single, atomic state. Each state should be self contained, and should request state transitions
## from the PlayerController.
## TODO: Need to make sure a null state can't instanced
class_name PlayerState
extends Node

## Reference to the owning PlayerController.
## This is set by the PlayerController on start.
var controller: PlayerController

## Reference to the PlayerInputHandler.
## This should ONLY be read from, never written to.
var input: PlayerInputHandler

## Called on entering the state from any other.
func enter() -> void: pass
## Called on exiting the state.
func exit() -> void: pass
## Called every physics update tick.
func physics_update(_delta: float) -> void: pass
