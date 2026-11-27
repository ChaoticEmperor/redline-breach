extends RefCounted
## Physics layer bits, one place. Walls and glass are WORLD; every character is an ACTOR;
## corpses and thrown things are BODIES; furniture and doors are PROPS.

const WORLD := 1
const ACTORS := 2
const BODIES := 4
const PROPS := 8
const SHOTS := WORLD | ACTORS | PROPS # what a bullet can hit
