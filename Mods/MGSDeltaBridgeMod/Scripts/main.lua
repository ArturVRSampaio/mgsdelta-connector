-- Real bridge for mgsdelta-connector's milestone 4 vertical slice.
--
-- Writes the live duck ("Gako") unlock counters to a state file on a
-- timer, and polls a commands file for write requests from the external
-- Python client (memory.py's FileBridge) -- see research/NOTES.md in
-- mgsdelta-connector for why file polling is the chosen IPC mechanism,
-- and mgsdelta-connector/research/probes/FrogFlagReaderMod for the manual
-- probe this replaces with an unattended, always-running version.

local json = require("json")

local STATE_PATH = "mgsdelta_state.json"
local COMMANDS_PATH = "mgsdelta_commands.json"
local POLL_INTERVAL_MS = 1000

local function WriteState()
    local KerotanSubsystem = FindFirstOf("BP_KerotanSubsystem_C")
    if not KerotanSubsystem or not KerotanSubsystem:IsValid() then
        return
    end

    local ok, status = pcall(function() return KerotanSubsystem:GetGakoUnlockStatus() end)
    if not ok or not status then
        return
    end

    local state = {
        duck_unlock_count = status.UnlockCount,
        duck_total_count = status.TotalCount,
    }

    local okEncode, encoded = pcall(json.encode, state)
    if not okEncode then
        print(string.format("[MGSDeltaBridge] Failed to encode state: %s\n", tostring(encoded)))
        return
    end

    local file, err = io.open(STATE_PATH, "w")
    if not file then
        print(string.format("[MGSDeltaBridge] Failed to open state file for writing: %s\n", tostring(err)))
        return
    end
    file:write(encoded)
    file:close()
end

-- FindAllOf is scoped to whatever level/sublevel is currently streamed in --
-- confirmed via research/NOTES.md's milestone 4 investigation: a duck's
-- GakoComponent only shows up here while the player is near it (loaded),
-- and disappears again once they move away and it streams back out. In
-- real play that's exactly when we need it: the player has to be near a
-- duck to interact with it, so it'll be loaded at that time. FindFirstOf
-- alone isn't enough though -- it can grab an already-collected instance
-- (learned the hard way, see milestone 3 notes) -- so search all live ones
-- for an actually-uncollected duck.
local function FindUncollectedGako()
    local components = FindAllOf("GakoComponent")
    if not components then
        return nil
    end
    for _, component in ipairs(components) do
        local ok, collected = pcall(function() return component.bColleted end)
        if ok and collected == false then
            return component
        end
    end
    return nil
end

local function HandleUnlockDuck()
    local component = FindUncollectedGako()
    if not component then
        print("[MGSDeltaBridge] unlock_duck: no uncollected GakoComponent found nearby, will retry\n")
        return false
    end

    local okCall = pcall(function() component:GakoSetCollected() end)
    if not okCall then
        return false
    end

    -- Verify the write actually took effect before declaring it handled,
    -- same rigor as the manual probe that confirmed this call works.
    local okCheck, collected = pcall(function() return component.bColleted end)
    return okCheck and collected == true
end

local function HandleCommand(command)
    if command.action == "unlock_duck" then
        return HandleUnlockDuck()
    end
    print(string.format("[MGSDeltaBridge] Unknown command action: %s\n", tostring(command.action)))
    return true -- drop unrecognized commands rather than retry them forever
end

local function ProcessCommands()
    local file = io.open(COMMANDS_PATH, "r")
    if not file then
        return -- no commands file yet, nothing to do
    end
    local content = file:read("*a")
    file:close()

    if not content or content == "" then
        return
    end

    local okDecode, commands = pcall(json.decode, content)
    if not okDecode or type(commands) ~= "table" then
        print(string.format("[MGSDeltaBridge] Failed to decode commands file: %s\n", tostring(commands)))
        return
    end

    local remaining = {}
    for _, command in ipairs(commands) do
        if not HandleCommand(command) then
            table.insert(remaining, command)
        end
    end

    if #remaining == 0 then
        os.remove(COMMANDS_PATH)
    else
        local okEncode, encoded = pcall(json.encode, remaining)
        if okEncode then
            local outFile = io.open(COMMANDS_PATH, "w")
            if outFile then
                outFile:write(encoded)
                outFile:close()
            end
        end
    end
end

LoopAsync(POLL_INTERVAL_MS, function()
    local ok, err = pcall(function()
        WriteState()
        ProcessCommands()
    end)
    if not ok then
        print(string.format("[MGSDeltaBridge] Tick failed: %s\n", tostring(err)))
    end
    return false -- keep looping forever
end)
