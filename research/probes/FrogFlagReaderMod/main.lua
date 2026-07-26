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

local function DumpClassMembers(Class)
    if not Class or not Class:IsValid() then return end
    local ok, fullName = pcall(function() return Class:GetFullName() end)
    print(string.format("[FrogFlagReader] -- Members of %s --\n", ok and fullName or "?"))

    Class:ForEachFunction(function(Function)
        local ok2, name = pcall(function() return Function:GetFullName() end)
        print(string.format("[FrogFlagReader]   Function: %s\n", ok2 and name or "?"))
    end)

    Class:ForEachProperty(function(Property)
        local ok3, name = pcall(function() return Property:GetFullName() end)
        print(string.format("[FrogFlagReader]   Property: %s\n", ok3 and name or "?"))
    end)
end

-- Walks the full class hierarchy (Blueprint layer + native parents) since
-- ForEachFunction/ForEachProperty only return members declared at that
-- exact level, not inherited ones.
local function DumpKerotanSubsystemMembers()
    local KerotanSubsystem = FindFirstOf("BP_KerotanSubsystem_C")
    if not KerotanSubsystem or not KerotanSubsystem:IsValid() then
        print("[FrogFlagReader] BP_KerotanSubsystem_C not found for member dump\n")
        return
    end

    local Class = KerotanSubsystem:GetClass()
    local Depth = 0
    while Class and Class:IsValid() and Depth < 10 do
        DumpClassMembers(Class)
        Class = Class:GetSuperStruct()
        Depth = Depth + 1
    end
end

-- Milestone 3 probe: find a live GakoComponent (the per-duck component,
-- /Script/MGS3.GakoComponent) and call GakoSetCollected() on it, to prove
-- the write path works. Reads bColleted before/after plus the aggregate
-- GetGakoUnlockStatus() counter, so we have two independent signals that
-- the write actually took effect.
local function TestGakoWrite()
    local AllGakoComps = FindAllOf("GakoComponent")
    if not AllGakoComps or #AllGakoComps == 0 then
        print("[FrogFlagReader] No GakoComponent instances found\n")
        return
    end

    print(string.format("[FrogFlagReader] Found %d GakoComponent instance(s)\n", #AllGakoComps))

    -- Find one that ISN'T already collected -- testing on an already-true
    -- one (like FindFirstOf grabbed last time) proves nothing.
    local GakoComp = nil
    for _, Comp in ipairs(AllGakoComps) do
        local ok, collected = pcall(function() return Comp.bColleted end)
        local okName2, name2 = pcall(function() return Comp:GetFullName() end)
        print(string.format("[FrogFlagReader]   candidate %s bColleted=%s\n",
            okName2 and name2 or "?", tostring(ok and collected or "?")))
        if ok and collected == false and not GakoComp then
            GakoComp = Comp
        end
    end

    if not GakoComp then
        print("[FrogFlagReader] Every found GakoComponent is already collected -- no uncollected duck available to test the write on\n")
        return
    end

    local okName, fullName = pcall(function() return GakoComp:GetFullName() end)
    print(string.format("[FrogFlagReader] GakoComponent: %s\n", okName and fullName or "?"))

    local okBefore, before = pcall(function() return GakoComp.bColleted end)
    print(string.format("[FrogFlagReader] bColleted BEFORE = %s\n", tostring(okBefore and before or "?")))

    local okCall, err = pcall(function() GakoComp:GakoSetCollected() end)
    print(string.format("[FrogFlagReader] GakoSetCollected() call ok=%s err=%s\n", tostring(okCall), tostring(err)))

    local okAfter, after = pcall(function() return GakoComp.bColleted end)
    print(string.format("[FrogFlagReader] bColleted AFTER = %s\n", tostring(okAfter and after or "?")))

    local KerotanSubsystem = FindFirstOf("BP_KerotanSubsystem_C")
    if KerotanSubsystem and KerotanSubsystem:IsValid() then
        local okStatus, status = pcall(function() return KerotanSubsystem:GetGakoUnlockStatus() end)
        if okStatus and status then
            print(string.format("[FrogFlagReader] Aggregate AFTER write: UnlockCount=%s TotalCount=%s\n",
                tostring(status.UnlockCount), tostring(status.TotalCount)))
        end
    end
end

-- Milestone 3 probe, take 2: GakoSetCollected is a one-shot (already true
-- for whichever duck FindAllOf happened to grab), so it can't prove a write
-- actually changes anything once a duck is already collected. Gako_Life
-- (an IntProperty on the BP_Gako_C actor, not the component) is repeatable
-- and reversible instead -- decrement it, verify, then restore the
-- original value so this probe doesn't leave a lasting change.
local function TestGakoLifeWrite()
    local GakoActor = FindFirstOf("BP_Gako_C")
    if not GakoActor or not GakoActor:IsValid() then
        print("[FrogFlagReader] BP_Gako_C actor not found\n")
        return
    end

    local okName, fullName = pcall(function() return GakoActor:GetFullName() end)
    print(string.format("[FrogFlagReader] BP_Gako_C: %s\n", okName and fullName or "?"))

    local okBefore, before = pcall(function() return GakoActor.Gako_Life end)
    print(string.format("[FrogFlagReader] Gako_Life BEFORE = %s\n", tostring(okBefore and before or "?")))

    if not okBefore or type(before) ~= "number" then
        print("[FrogFlagReader] Could not read Gako_Life as a number, aborting write test\n")
        return
    end

    local newValue = before - 1
    local okSet, setErr = pcall(function() GakoActor:SetPropertyValue("Gako_Life", newValue) end)
    print(string.format("[FrogFlagReader] SetPropertyValue(Gako_Life, %s) ok=%s err=%s\n",
        tostring(newValue), tostring(okSet), tostring(setErr)))

    local okAfter, after = pcall(function() return GakoActor.Gako_Life end)
    print(string.format("[FrogFlagReader] Gako_Life AFTER = %s\n", tostring(okAfter and after or "?")))

    -- Restore the original value so this probe doesn't leave a lasting change.
    local okRestoreCall = pcall(function() GakoActor:SetPropertyValue("Gako_Life", before) end)
    local okRestored, restored = pcall(function() return GakoActor.Gako_Life end)
    print(string.format("[FrogFlagReader] Gako_Life RESTORED (call ok=%s) = %s\n",
        tostring(okRestoreCall), tostring(okRestored and restored or "?")))
end

-- Manual triggers:
--   Ctrl+Num9: read known counters
--   Ctrl+Num8: dump every function/property on the subsystem's full class hierarchy
--   Ctrl+Num7: milestone 3 write test v1 (GakoSetCollected on a live duck -- one-shot, kept for reference)
--   Ctrl+Num6: milestone 3 write test v2 (Gako_Life decrement/restore -- repeatable)
RegisterKeyBind(Key.NUM_NINE, {ModifierKey.CONTROL}, ReadKerotanStatus)
RegisterKeyBind(Key.NUM_EIGHT, {ModifierKey.CONTROL}, DumpKerotanSubsystemMembers)
RegisterKeyBind(Key.NUM_SEVEN, {ModifierKey.CONTROL}, TestGakoWrite)
RegisterKeyBind(Key.NUM_SIX, {ModifierKey.CONTROL}, TestGakoLifeWrite)

-- Also try automatically a few seconds after the mod loads, in case the
-- game is already in a gameplay session. TestGakoWrite is NOT auto-run --
-- it has a real, permanent side effect on the save, so it only runs on the
-- explicit Ctrl+Num7 keybind.
ExecuteWithDelay(5000, ReadKerotanStatus)
ExecuteWithDelay(5500, DumpKerotanSubsystemMembers)
