-- Recon script for mgsdelta-connector milestone 2 ("read one flag").
-- Reads the live BP_KerotanSubsystem_C GameInstanceSubsystem and prints its
-- frog/gako unlock counters to UE4SS.log. Not part of any real mod, just a
-- throwaway probe for this session.

local function ReadKerotanStatus()
    local KerotanSubsystem = FindFirstOf("BP_KerotanSubsystem_C")
    if not KerotanSubsystem or not KerotanSubsystem:IsValid() then
        print("[FrogFlagReader] BP_KerotanSubsystem_C not found\n")
        return
    end

    print(string.format("[FrogFlagReader] Found KerotanSubsystem at %s\n", tostring(KerotanSubsystem:GetAddress())))

    local ok1, GakoStatus = pcall(function() return KerotanSubsystem:GetGakoUnlockStatus() end)
    if ok1 and GakoStatus then
        print(string.format("[FrogFlagReader] GetGakoUnlockStatus -> UnlockCount=%s TotalCount=%s IsExistInCurrentArea=%s IsUnlcokedInCurrentArea=%s\n",
            tostring(GakoStatus.UnlockCount), tostring(GakoStatus.TotalCount),
            tostring(GakoStatus.IsExistInCurrentArea), tostring(GakoStatus.IsUnlcokedInCurrentArea)))
    else
        print(string.format("[FrogFlagReader] GetGakoUnlockStatus call failed: %s\n", tostring(GakoStatus)))
    end

    local ok2, MapStatus = pcall(function() return KerotanSubsystem:GetCurrentMapKerotanStatus() end)
    if ok2 and MapStatus then
        print(string.format("[FrogFlagReader] GetCurrentMapKerotanStatus -> UnlockCount=%s TotalCount=%s IsExistInCurrentArea=%s IsUnlcokedInCurrentArea=%s\n",
            tostring(MapStatus.UnlockCount), tostring(MapStatus.TotalCount),
            tostring(MapStatus.IsExistInCurrentArea), tostring(MapStatus.IsUnlcokedInCurrentArea)))
    else
        print(string.format("[FrogFlagReader] GetCurrentMapKerotanStatus call failed: %s\n", tostring(MapStatus)))
    end

    local ok3, KerotanStatus = pcall(function() return KerotanSubsystem:GetKerotanUnlockStatus() end)
    if ok3 and KerotanStatus then
        print(string.format("[FrogFlagReader] GetKerotanUnlockStatus -> bIsUnlocked=%s bHasKerotan=%s\n",
            tostring(KerotanStatus.bIsUnlocked), tostring(KerotanStatus.bHasKerotan)))
    else
        print(string.format("[FrogFlagReader] GetKerotanUnlockStatus call failed: %s\n", tostring(KerotanStatus)))
    end
end

-- Manual trigger: Ctrl+Num9 (unused by any other bundled mod).
RegisterKeyBind(Key.NUM_NINE, {ModifierKey.CONTROL}, ReadKerotanStatus)

-- Also try automatically a few seconds after the mod loads, in case the
-- game is already in a gameplay session.
ExecuteWithDelay(5000, ReadKerotanStatus)
