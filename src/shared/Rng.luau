--!strict
--[[
	Rng: injectable random number source.

	The rules engine never calls math.random / Random directly so that
	  * the server can use Roblox's Random.new() (Rng.fromRandom)
	  * unit tests can use a seeded deterministic generator (Rng.fromSeed)
	  * a future "manual dice" rule can supply its own generator.
]]

export type Rng = {
	nextInt: (self: Rng, min: number, max: number) -> number,
}

local Rng = {}

-- Deterministic xorshift32 generator (pure Luau, works in Roblox and Lune).
function Rng.fromSeed(seed: number): Rng
	local state = bit32.band(math.floor(seed), 0xFFFFFFFF)
	if state == 0 then
		state = 0x9E3779B9
	end
	local rng = {} :: any
	function rng.nextInt(_self: Rng, min: number, max: number): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return min + (state % (max - min + 1))
	end
	return rng :: Rng
end

-- Wrap a Roblox Random object.
function Rng.fromRandom(random: any): Rng
	local rng = {} :: any
	function rng.nextInt(_self: Rng, min: number, max: number): number
		return random:NextInteger(min, max)
	end
	return rng :: Rng
end

-- Fisher-Yates shuffle in place. Returns the same list.
function Rng.shuffle<T>(rng: Rng, list: { T }): { T }
	for i = #list, 2, -1 do
		local j = rng:nextInt(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

return Rng
